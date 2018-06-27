
from . import config, validate

import numpy as np
from os import urandom
from time import time

# TODO: wrap some of the most common functions of PETSc vectors -- like norm, binary operators, etc.
# could probably do it in some clever way

class State:
    """
    Class representing a state.

    Parameters
    ----------

    L : int
        Spin chain length. Can be ommitted if config.L is set.

    subspace : dynamite.subspace.Subspace, optional
        The subspace on which the state should be defined.
        If not specified, defaults to config.subspace.

    state : int or str, optional
        An initial product state to set the state to. Also accepts ``'random'``. The
        state can also be initialized later with the :meth:`set_product` and
        :meth:`set_random` methods.

    seed : int, optional
        If the ``state`` argument is set to ``'random'``, the seed for the random number
        generator. This argument is ignored otherwise.
    """

    def __init__(self, L = None, subspace = None, state = None, seed = None):

        config.initialize()
        from petsc4py import PETSc

        if L is None:
            L = config.L

        self.L = validate.L(L)

        if subspace is None:
            subspace = config.subspace

        self._subspace = validate.subspace(subspace)
        self._subspace.L = self.L

        self._vec = PETSc.Vec().create()
        self.vec.setSizes(subspace.get_dimension())
        self.vec.setFromOptions()

        if state is not None:
            if state == 'random':
                self.set_random(seed=seed)
            else:
                self.set_product(state)

    def copy(self):
        rtn = State(self.L, self.subspace.copy())
        self.vec.copy(rtn.vec)
        return rtn

    @property
    def subspace(self):
        """
        The space on which the vector is defined.

        See :module:`dynamite.subspace` for details.
        """
        return self._subspace

    @property
    def vec(self):
        """
        The PETSc vector containing the state data.

        petsc4py Vec methods can be used through this interface--for example, to find the norm of a
        State `s`, one can do `state.vec.norm()`. The methods don't seem to be documented anywhere,
        but are fairly transparent from looking at the petsc4py source code.
        """
        return self._vec

    @classmethod
    def _str_to_idx(cls, s, state_to_idx, L):
        '''
        Convert a string (either a bitstring of type int or a Python string) to
        a state index. If an int, the binary representation represents the spin
        configuration (0=↓, 1=↑) of a product state. If a Python string, the characters
        'D' and 'U' represent down and up spins, like ``"DUDDU...UDU"`` (D=↓, U=↑).

        .. note::
            For the string representation, the leftmost character is spin index 0. For
            an integer representation, the rightmost (least significant) bit is!

        Parameters
        ----------
        s : int or string
            The state

        state_to_idx : function(int)
            A function that converts an integer representing a state to the index of
            the corresponding basis state in the Hilbert space.

        L : int
            The length of the spin chain

        Returns
        -------
        int
            The index in the Hilbert space
        '''

        if isinstance(s, str):
            if len(s) != L:
                raise ValueError('state string must have length L')

            if not all(c in ['U','D'] for c in str(s)):
                raise ValueError('only character U and D allowed in state')

            state = 0
            for i,c in enumerate(s):
                if c == 'U':
                    state += 1<<i

        elif isinstance(s, int):
            state = s

        else:
            raise TypeError('State must be an int or str.')

        return state_to_idx(state)

    def set_product(self, s):
        """
        Initialize to a product state. Can be specified either be an integer whose binary
        representation represents the spin configuration (0=↓, 1=↑) of a product state, or a string
        of the form ``"DUDDU...UDU"`` (D=↓, U=↑). If it is a string, the string's length must
        equal ``L``.

        .. note:
            In integer representation, the least significant bit represents spin 0. So, if you look
            at a binary representation of the integer (for example with Python's `bin` function)
            spin 0 will be the rightmost bit!

        Parameters
        ----------

        s : int or str
            A representation of the state.
        """

        idx = self._str_to_idx(s, self.subspace.state_to_idx, self.L)

        self.vec.set(0)

        istart, iend = self.vec.getOwnershipRange()
        if istart <= idx < iend:
            self.vec[idx] = 1

        self.vec.assemblyBegin()
        self.vec.assemblyEnd()

    @classmethod
    def generate_time_seed(cls):

        config.initialize()
        from petsc4py import PETSc

        CW = PETSc.COMM_WORLD.tompi4py()

        if CW.rank == 0:
            seed = int(time())
        else:
            seed = None

        return CW.bcast(seed, root = 0)

    def set_random(self, seed = None, normalize = True):
        """
        Initialized to a normalized random state.

        .. note::
            When running under MPI with multiple processes, the seed is incremented
            by the MPI rank, so that each process generates different random values.

        Parameters
        ----------

        seed : int, optional
            A seed for numpy's PRNG that is used to build the random state. The user
            should pass the same value on every process.

        normalize : bool
            Whether to rescale the random state to have norm 1.
        """

        config.initialize()
        from petsc4py import PETSc

        istart, iend = self.vec.getOwnershipRange()

        R = np.random.RandomState()

        if seed is None:
            try:
                seed = int.from_bytes(urandom(4), 'big', signed=False)
            except NotImplementedError:
                seed = self.generate_time_seed()

        # if my code is still being used in year 2038, wouldn't want it to
        # overflow numpy's PRNG seed range ;)
        R.seed((seed + PETSc.COMM_WORLD.rank) % 2**32)

        local_size = iend-istart
        self.vec[istart:iend] =    R.standard_normal(local_size) + \
                                1j*R.standard_normal(local_size)

        self.vec.assemblyBegin()
        self.vec.assemblyEnd()

        if normalize:
            self.vec.normalize()

    @classmethod
    def _to_numpy(cls, vec, to_all = False):
        '''
        Collect PETSc vector (split across processes) to a
        numpy array on process 0, or to all processes if
        `to_all == True`.

        Parameters
        ----------
        vec : petsc4py.PETSc.Vec
            The input vector

        to_all : bool, optional
            Whether to create numpy vectors on all processes, or
            just on process 0.

        Returns
        -------
        numpy.ndarray or None
            A numpy array of the vector, or ``None``
            on all processes other than 0 if `to_all == False`.
        '''

        from petsc4py import PETSc

        # collect to process 0
        if to_all:
            sc, v0 = PETSc.Scatter.toAll(vec)
        else:
            sc, v0 = PETSc.Scatter.toZero(vec)

        sc.begin(vec, v0)
        sc.end(vec, v0)

        if not to_all and PETSc.COMM_WORLD.rank != 0:
            return None

        ret = np.ndarray((v0.getSize(),), dtype=np.complex128)
        ret[:] = v0[:]

        return ret

    def to_numpy(self, to_all = False):
        """
        Return a numpy representation of the state.

        Parameters
        ----------
        to_all : bool
            Whether to return the vector on all MPI ranks (True),
            or just rank 0 (False).
        """
        return self._to_numpy(self.vec, to_all)

    # TODO: should I try to be clever about this
    def norm(self):
        return self.vec.norm()

    def dot(self, x):
        return self.vec.dot(x.vec)