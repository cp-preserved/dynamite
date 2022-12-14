'''
Integration tests for states.
'''

import numpy as np

import dynamite_test_runner as dtr

from dynamite import config
from dynamite.states import State, UninitializedError
from dynamite.subspaces import Parity, SpinConserve, Auto
from dynamite.operators import sigmaz, sigmax, sigmay, index_sum
from dynamite.computations import reduced_density_matrix

class RandomSeed(dtr.DynamiteTestCase):

    def test_generation(self):
        '''
        Make sure that different processors get the same random seed.
        '''

        from dynamite import config
        config._initialize()
        from petsc4py import PETSc

        seed = State.generate_time_seed()

        if PETSc.COMM_WORLD.size > 1:
            comm = PETSc.COMM_WORLD.tompi4py()
            all_seeds = comm.gather(seed, root=0)
        else:
            all_seeds = [seed]

        if PETSc.COMM_WORLD.rank == 0:
            self.assertTrue(all(s == seed for s in all_seeds))

class ToNumpy(dtr.DynamiteTestCase):

    def setUp(self):
        from petsc4py import PETSc

        self.v = PETSc.Vec().create()
        self.v.setSizes(PETSc.COMM_WORLD.size)
        self.v.setFromOptions()
        self.v.set(-1)

        self.v[PETSc.COMM_WORLD.rank] = PETSc.COMM_WORLD.rank
        self.v.assemblyBegin()
        self.v.assemblyEnd()

    def test_to_zero(self):
        from petsc4py import PETSc
        npvec = State._to_numpy(self.v)
        if PETSc.COMM_WORLD.rank == 0:
            for i in range(PETSc.COMM_WORLD.rank):
                self.assertTrue(npvec[i] == i)
        else:
            self.assertIs(npvec, None)

    def test_to_all(self):
        from petsc4py import PETSc
        npvec = State._to_numpy(self.v, to_all = True)
        for i in range(PETSc.COMM_WORLD.rank):
            self.assertTrue(npvec[i] == i)

class PetscMethods(dtr.DynamiteTestCase):
    '''
    Tests that the methods directly included from PETSc function as intended.
    '''
    def test_norm(self):
        state = State()
        start, end = state.vec.getOwnershipRange()
        state.vec[start:end] = np.array([1]*(end-start))
        state.vec.assemblyBegin()
        state.vec.assemblyEnd()
        state.set_initialized()
        self.assertAlmostEqual(state.norm()**2, state.subspace.get_dimension())

    def test_normalize(self):
        state = State()
        start, end = state.vec.getOwnershipRange()
        state.vec[start:end] = np.array([1]*(end-start))
        state.vec.assemblyBegin()
        state.vec.assemblyEnd()
        state.set_initialized()

        state.normalize()
        self.assertTrue(state.norm() == 1)

    def test_copy_preallocate(self):
        state1 = State()
        state2 = State()
        start, end = state1.vec.getOwnershipRange()
        state1.vec[start:end] = np.arange(start, end)
        state1.vec.assemblyBegin()
        state1.vec.assemblyEnd()
        state1.set_initialized()

        result = np.ndarray((end-start,), dtype=np.complex128)
        state1.copy(state2)
        result[:] = state2.vec[start:end]

        self.assertTrue(np.array_equal(result, np.arange(start, end)))

    def test_copy_exception_L(self):
        state1 = State(subspace=Parity('even'))
        state2 = State(subspace=Parity('odd'))

        with self.assertRaises(ValueError):
            state1.copy(state2)

    def test_copy_nopreallocate(self):
        state1 = State()
        start, end = state1.vec.getOwnershipRange()
        state1.vec[start:end] = np.arange(start, end)
        state1.vec.assemblyBegin()
        state1.vec.assemblyEnd()
        state1.set_initialized()

        result = np.ndarray((end-start,), dtype=np.complex128)
        state2 = state1.copy()
        result[:] = state2.vec[start:end]

        self.assertTrue(np.array_equal(result, np.arange(start, end)))

    def test_scale(self):
        vals = [2, 3.14]
        for val in vals:
            with self.subTest(val=val):
                state = State(state='random')
                start, end = state.vec.getOwnershipRange()
                pre_values = np.ndarray((end-start,), dtype=np.complex128)
                pre_values[:] = state.vec[start:end]

                state *= val

                for i in range(start, end):
                    self.assertEqual(state.vec[i], val*pre_values[i-start])

    def test_scale_divide(self):
        val = 3.14
        state = State(state='random')
        start, end = state.vec.getOwnershipRange()
        pre_values = np.ndarray((end-start,), dtype=np.complex128)
        pre_values[:] = state.vec[start:end]

        state /= val

        for i in range(start, end):
            self.assertEqual(state.vec[i], (1/val)*pre_values[i-start])

    def test_scale_exception_ary(self):
        val = np.array([3.1, 4])
        state = State(state='U'*config.L)
        with self.assertRaises(TypeError):
            state *= val

    def test_scale_exception_vec(self):
        state1 = State(state='U'*config.L)
        state2 = State(state='U'*config.L)
        with self.assertRaises(TypeError):
            state1 *= state2


class Projection(dtr.DynamiteTestCase):

    def check_projection(self, state, idx):
        for val in (0, 1):
            with self.subTest(value=val):
                proj_state = state.copy()

                proj_state.project(idx, val)

                sz = sigmaz(idx)
                sz.add_subspace(state.subspace)

                self.assertAlmostEqual(
                    proj_state.dot(sz*proj_state),
                    1 if val == 0 else -1
                )

    def test_full(self):
        state = State(state='random')

        for idx in [0, config.L//2, config.L-1]:
            with self.subTest(idx=idx):
                self.check_projection(state, idx)

    def test_parity(self):
        for parity in ['odd', 'even']:
            with self.subTest(parity=parity):

                state = State(subspace=Parity(parity),
                              state='random')
                for idx in [0, config.L//2, config.L-1]:
                    with self.subTest(idx=idx):
                        self.check_projection(state, idx)

    def test_index_exceptions(self):
        state = State(state='random')
        for idx in [-1, config.L, config.L+1]:
            with self.subTest(idx=idx):
                with self.assertRaises(ValueError):
                    state.project(idx, 0)

    def test_value_exception(self):
        state = State(state='random')
        with self.assertRaises(ValueError):
            state.project(0, -1)


class Saving(dtr.DynamiteTestCase):

    fname = '/tmp/dnm_test_save'

    def check_states_equal(self, a, b):
        self.assertTrue(a.subspace.identical(b.subspace))
        self.assertTrue(a.vec.equal(b.vec))

    def test_save_simple(self):
        state = State(state='random')
        state.save(self.fname)
        loaded = State.from_file(self.fname)
        self.check_states_equal(state, loaded)

    def test_save_parity(self):
        subspace = Parity('even')
        state = State(state='random', subspace=subspace)
        state.save(self.fname)
        loaded = State.from_file(self.fname)
        self.check_states_equal(state, loaded)

    def test_save_spinconserve(self):
        subspace = SpinConserve(config.L, config.L//2)
        state = State(state='random', subspace=subspace)
        state.save(self.fname)
        loaded = State.from_file(self.fname)
        self.check_states_equal(state, loaded)

    def test_save_spinconserve_spinflip(self):
        subspace = SpinConserve(config.L, config.L//2, spinflip=True)
        state = State(state='random', subspace=subspace)
        state.save(self.fname)
        loaded = State.from_file(self.fname)
        self.check_states_equal(state, loaded)

    def test_save_auto(self):
        H = index_sum(sigmax(0)*sigmax(1) + sigmay(0)*sigmay(1))

        half_L = config.L//2
        subspace = Auto(H, 'U'*half_L + 'D'*(config.L - half_L))
        state = State(state='random', subspace=subspace)
        state.save(self.fname)
        loaded = State.from_file(self.fname)
        self.check_states_equal(state, loaded)


class Uninitialized(dtr.DynamiteTestCase):

    def test_copy_neither(self):
        s0 = State()
        s1 = s0.copy()
        self.assertFalse(s1.initialized)

    def test_copy_from_uninit(self):
        s0 = State()
        s1 = State(state='U'*config.L)
        with self.assertRaises(UninitializedError):
            s0.copy(s1)

    def test_copy_to_uninit(self):
        s0 = State(state='U'*config.L)
        s1 = State()
        s0.copy(s1)
        self.assertTrue(s1.initialized)

    def test_project(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0.project(0, 0)

    def test_to_numpy(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0.to_numpy()

    def test_dot_from(self):
        s0 = State()
        s1 = State(state='U'*config.L)
        with self.assertRaises(UninitializedError):
            s0.dot(s1)

    def test_dot_to(self):
        s0 = State(state='U'*config.L)
        s1 = State()
        with self.assertRaises(UninitializedError):
            s0.dot(s1)

    def test_norm(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0.norm()

    def test_normalize(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0.normalize()

    def test_imul(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0 *= 2

    def test_idiv(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            s0 /= 2

    def test_op_dot(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            sigmax().dot(s0)

    def test_op_evolve(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            sigmax().evolve(s0, t=1.0)

    def test_rdm(self):
        s0 = State()
        with self.assertRaises(UninitializedError):
            reduced_density_matrix(s0, [])

# TODO: check state setting. e.g. setting an invalid state should fail (doesn't for Full subspace)

if __name__ == '__main__':
    dtr.main()
