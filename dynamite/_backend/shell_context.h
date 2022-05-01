
#include <petsc.h>

typedef struct _msc_t {
  PetscInt nmasks;
  PetscInt* masks;
  PetscInt* mask_offsets;
  PetscInt* signs;
  PetscScalar* coeffs;
} msc_t;

typedef struct _shell_context {
  PetscInt nmasks_local;
  PetscInt nmasks;
  PetscInt* masks;
  PetscInt* mask_offsets;
  PetscInt* signs;
  PetscReal* real_coeffs;     // we store only the real or complex part -- whichever is nonzero
  void *left_subspace_data;
  void *right_subspace_data;
  PetscReal nrm;

  VecScatter sc_ctx; // context for scattering
  Vec x_all; // sequential x array
} shell_context;
