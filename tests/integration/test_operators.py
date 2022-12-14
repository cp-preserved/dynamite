'''
Integration tests for operators.
'''

import dynamite_test_runner as dtr

from dynamite import config
from dynamite.tools import complex_enabled
from dynamite.subspaces import Full, Parity, SpinConserve, Auto
from dynamite.operators import index_sum, sigmax, sigmay, sigmaz

import hamiltonians


class SubspaceConservation(dtr.DynamiteTestCase):
    """
    Tests ensuring that dynamite correctly checks whether
    a given subspace is conserved or not.
    """

    def test_full(self):
        for H_name in hamiltonians.get_names(complex_enabled()):
            with self.subTest(H=H_name):
                H = getattr(hamiltonians, H_name)()
                self.assertTrue(H.conserves(Full()))

    def test_parity(self):
        answers = {
            'localized': True,
            'syk': True,
            'ising': False,
            'long_range': False
        }

        for parity in ('even', 'odd'):
            for H_name in hamiltonians.get_names(complex_enabled()):
                H = getattr(hamiltonians, H_name)()
                with self.subTest(H=H_name, parity=parity):
                    self.assertEqual(
                        H.conserves(Parity(parity)),
                        answers[H_name]
                    )

    def test_spinconserve(self):
        answers = {
            'localized': True,
            'syk': False,
            'ising': False,
            'long_range': False
        }

        for k in (config.L//2, config.L//4):
            for H_name in hamiltonians.get_names(complex_enabled()):
                H = getattr(hamiltonians, H_name)()
                with self.subTest(H=H_name, L=config.L, k=k):
                    self.assertEqual(
                        H.conserves(SpinConserve(config.L, k)),
                        answers[H_name]
                    )

    def test_spinconserve_spinflip_false(self):
        L = config.L

        if L % 2 != 0:
            self.skipTest("only for even spin chain lengths")

        k = config.L//2
        for spinflip in ('+', '-'):
            for H_name in hamiltonians.get_names(complex_enabled()):
                H = getattr(hamiltonians, H_name)()
                with self.subTest(H=H_name, spinflip=spinflip):
                    self.assertFalse(
                        H.conserves(SpinConserve(
                            config.L, k, spinflip=spinflip
                        ))
                    )

    def test_spinconserve_spinflip_heisenberg(self):
        H = index_sum(
            sigmax(0)*sigmax(1) + sigmay(0)*sigmay(1) + sigmaz(0)*sigmaz(1)
        )

        L = config.L
        if L % 2 != 0:
            self.skipTest("only for even spin chain lengths")

        k = config.L//2
        for spinflip in ('+', '-'):
            with self.subTest(spinflip=spinflip):
                self.assertTrue(
                    H.conserves(SpinConserve(
                        config.L, k, spinflip=spinflip
                    ))
                )

    def test_spinconserve_spinflip_error(self):
        op = sigmax()
        with self.assertRaises(ValueError):
            op.conserves(
                SpinConserve(config.L, config.L//2, spinflip='+'),
                Full()
            )

    def test_auto(self):
        for k in (config.L//2, config.L//4):
            for H_name in hamiltonians.get_names(complex_enabled()):
                H = getattr(hamiltonians, H_name)()
                subspace = Auto(H, 'U'*k + 'D'*(config.L-k))
                with self.subTest(H=H_name, L=config.L, k=k):
                    self.assertTrue(
                        H.conserves(subspace)
                    )

    def test_change_parity(self):
        """
        Test going from one parity subspace to the other
        """
        op = sigmax()

        with self.subTest(from_space='odd', to_space='even'):
            self.assertTrue(
                op.conserves(Parity('even'), Parity('odd'))
            )

        with self.subTest(from_space='even', to_space='odd'):
            self.assertTrue(
                op.conserves(Parity('odd'), Parity('even'))
            )

    def test_change_spinflip(self):
        """
        Test operators that take us from one spinflip value to the other
        """
        L = config.L
        if L % 2 != 0:
            self.skipTest("only for even spin chain lengths")
        k = config.L//2

        op = sigmaz()

        self.assertTrue(
            op.conserves(
                SpinConserve(config.L, k, spinflip='+'),
                SpinConserve(config.L, k, spinflip='-')
            )
        )

        self.assertTrue(
            op.conserves(
                SpinConserve(config.L, k, spinflip='-'),
                SpinConserve(config.L, k, spinflip='+')
            )
        )

    def test_full_to_others(self):
        """
        all these subspaces should fail projecting from full space
        """
        subspaces = [
            ('parity_even', Parity('even')),
            ('parity_odd', Parity('odd')),
            ('spinconserve', SpinConserve(config.L, config.L//2))
        ]
        for H_name in hamiltonians.get_names(complex_enabled()):
            with self.subTest(H=H_name):
                H = getattr(hamiltonians, H_name)()
                for subspace_name, subspace in subspaces:
                    with self.subTest(subspace=subspace_name):
                        self.assertFalse(H.conserves(
                            subspace,
                            Full()
                        ))


if __name__ == '__main__':
    dtr.main()
