'''
Test correctness of matvec for various cases.
'''

import unittest as ut
import numpy as np
import hamiltonians
from dynamite.operators import identity, sigmax, sigmay, index_sum, index_product
from dynamite.subspace import Full, Parity
from dynamite.states import State

class FullSpace(ut.TestCase):

    def check_nonzeros(self, state, nonzeros):
        '''
        Check that a vector has the correct nonzeros.

        Parameters
        ----------
        state : dynamite.states.State
            The state containing the vector

        nonzeros : dict
            A dictionary, where the keys are the indices of the nonzero elements
            and the values are the nonzero values
        '''
        istart, iend = state.vec.getOwnershipRange()
        for i in range(istart, iend):
            if i in nonzeros:
                self.assertEqual(state.vec[i], nonzeros[i], msg = 'idx: %d' % i)
            else:
                self.assertEqual(state.vec[i], 0, msg = 'idx: %d' % i)

    def test_identity(self):
        s = State(state = 10)
        r = identity() * s
        correct = {10 : 1}
        self.check_nonzeros(r, correct)

    def test_spinflip(self):
        H = index_product(sigmax())
        s = State(state = 'U'*H.get_length())
        r = H * s
        correct = {0 : 1}
        self.check_nonzeros(r, correct)

class Hamiltonians(ut.TestCase):

    def test_all(self):
        for H_name in hamiltonians.__all__:
            with self.subTest(H = H_name):
                H = getattr(hamiltonians, H_name)()
                bra, ket = H.create_states()
                ket.set_random(seed = 0)

                H_np = H.to_numpy()
                ket_np = ket.to_numpy()

                H.dot(ket, bra)
                bra_check = bra.to_numpy()

                if ket_np is not None:
                    bra_np = H_np.dot(ket_np)
                    inner_prod = bra_check.dot(bra_np.conj())
                    inner_prod /= np.linalg.norm(bra_check) * np.linalg.norm(bra_np)
                    self.assertLess(np.abs(1 - inner_prod), 1E-9)

class Subspaces(ut.TestCase):

    def compare_to_full(self, H, x, check_subspace):
        '''
        Compare multiplication under the full Hamiltonian to multiplication
        in the subspace.

        Parameters
        ----------
        H : dynamite.operators.Operator
            The operator to multiply.

        x : dynamite.states.State
            The state to multiply (subspace should be Full)

        check_subspace : dynamite.subspace.Subspace
            The subspace to multiply under.
        '''
        to_space = identity()
        to_space.right_subspace = Full()
        to_space.left_subspace = check_subspace

        H.left_subspace = Full()
        H.right_subspace = Full()
        y_f2f = H * x
        y_f2f = to_space * y_f2f

        H.left_subspace = check_subspace
        y_f2s = H * x

        H.right_subspace = check_subspace
        x_s = to_space * x
        y_s2s = H * x_s

        istart, iend = y_f2f.vec.getOwnershipRange()
        local_f2f = y_f2f.vec[istart:iend]
        local_f2s = y_f2s.vec[istart:iend]
        local_s2s = y_s2s.vec[istart:iend]

        self.assertTrue(np.array_equal(local_f2f, local_f2s))
        self.assertTrue(np.array_equal(local_f2f, local_s2s))

    def test_parity_XX_even(self):
        H = index_sum(sigmax(0)*sigmax(1))
        x = State(state = 0)
        sp = Parity('even')
        self.compare_to_full(H, x, sp)

    def test_parity_XX_odd(self):
        H = index_sum(sigmax(0)*sigmax(1))
        x = State(state = 1)
        sp = Parity('odd')
        self.compare_to_full(H, x, sp)

    def test_parity_YY_even(self):
        H = index_sum(sigmay(0)*sigmay(1))
        x = State(state = 0)
        sp = Parity('even')
        self.compare_to_full(H, x, sp)

    def test_parity_YY_odd(self):
        H = index_sum(sigmay(0)*sigmay(1))
        x = State(state = 1)
        sp = Parity('odd')
        self.compare_to_full(H, x, sp)

if __name__ == '__main__':
    from dynamite import config
    config.L = 10
    config.shell = False
    ut.main()