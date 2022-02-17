
#include "bpetsc_impl.h"

/*
 * For efficiency, we avoid going through cases of each subspace in the functions
 * defined in builmat_template.c. Instead, we just include the template multiple
 * times, using macros to define different functionality.

 */

// defines used in the various templates
#define Full_SP 0
#define Parity_SP 1
#define SpinConserve_SP 2
#define Explicit_SP 3


#define SUBSPACE Full
  #include "bpetsc_template_1.c"
#undef SUBSPACE

#define SUBSPACE Parity
  #include "bpetsc_template_1.c"
#undef SUBSPACE

#define SUBSPACE SpinConserve
  #include "bpetsc_template_1.c"
#undef SUBSPACE

#define SUBSPACE Explicit
  #include "bpetsc_template_1.c"
#undef SUBSPACE

#undef  __FUNCT__
#define __FUNCT__ "ReducedDensityMatrix"
PetscErrorCode ReducedDensityMatrix(
  Vec vec,
  PetscInt sub_type,
  void* sub_data_p,
  PetscInt keep_size,
  PetscInt* keep,
  PetscBool triang,
  PetscInt rtn_dim,
  PetscScalar* rtn
){
  PetscErrorCode ierr;
  switch (sub_type) {
    case FULL:
      ierr = rdm_Full(vec, sub_data_p, keep_size, keep, triang, rtn_dim, rtn);CHKERRQ(ierr);
      break;
    case PARITY:
      ierr = rdm_Parity(vec, sub_data_p, keep_size, keep, triang, rtn_dim, rtn);CHKERRQ(ierr);
      break;
    case SPIN_CONSERVE:
      ierr = rdm_SpinConserve(vec, sub_data_p, keep_size, keep, triang, rtn_dim, rtn);CHKERRQ(ierr);
      break;
    case EXPLICIT:
      ierr = rdm_Explicit(vec, sub_data_p, keep_size, keep, triang, rtn_dim, rtn);CHKERRQ(ierr);
      break;
    default: // shouldn't happen, but give ierr some (nonzero) value for consistency
      ierr = 1;
      break;
  }
  return ierr;
}

#define LEFT_SUBSPACE Full
  #define RIGHT_SUBSPACE Full
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Parity
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE SpinConserve
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Explicit
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE
#undef LEFT_SUBSPACE

#define LEFT_SUBSPACE Parity
  #define RIGHT_SUBSPACE Full
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Parity
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE SpinConserve
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Explicit
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE
#undef LEFT_SUBSPACE

#define LEFT_SUBSPACE SpinConserve
  #define RIGHT_SUBSPACE Full
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Parity
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE SpinConserve
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Explicit
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE
#undef LEFT_SUBSPACE

#define LEFT_SUBSPACE Explicit
  #define RIGHT_SUBSPACE Full
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Parity
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE SpinConserve
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE

  #define RIGHT_SUBSPACE Explicit
    #include "bpetsc_template_2.c"
  #undef RIGHT_SUBSPACE
#undef LEFT_SUBSPACE

/*
 * Build the matrix using the appropriate BuildMat function for the subspaces.
 */
PetscErrorCode BuildMat(const msc_t *msc, subspaces_t *subspaces, shell_impl shell, Mat *A)
{
  PetscErrorCode ierr = 0;
  switch (subspaces->left_type) {
    case FULL:
      switch (subspaces->right_type) {
        case FULL:
          ierr = BuildMat_Full_Full(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case PARITY:
          ierr = BuildMat_Full_Parity(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case SPIN_CONSERVE:
          ierr = BuildMat_Full_SpinConserve(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case EXPLICIT:
          ierr = BuildMat_Full_Explicit(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;
      }
      break;

    case PARITY:
      switch (subspaces->right_type) {
        case FULL:
          ierr = BuildMat_Parity_Full(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case PARITY:
          ierr = BuildMat_Parity_Parity(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case SPIN_CONSERVE:
          ierr = BuildMat_Parity_SpinConserve(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case EXPLICIT:
          ierr = BuildMat_Parity_Explicit(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;
      }
      break;

    case SPIN_CONSERVE:
      switch (subspaces->right_type) {
        case FULL:
          ierr = BuildMat_SpinConserve_Full(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case PARITY:
          ierr = BuildMat_SpinConserve_Parity(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

      case SPIN_CONSERVE:
          ierr = BuildMat_SpinConserve_SpinConserve(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case EXPLICIT:
          ierr = BuildMat_SpinConserve_Explicit(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;
      }
      break;

    case EXPLICIT:
      switch (subspaces->right_type) {
        case FULL:
          ierr = BuildMat_Explicit_Full(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case PARITY:
          ierr = BuildMat_Explicit_Parity(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

      case SPIN_CONSERVE:
          ierr = BuildMat_Explicit_SpinConserve(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;

        case EXPLICIT:
          ierr = BuildMat_Explicit_Explicit(msc, subspaces->left_data, subspaces->right_data, shell, A);
          break;
      }
      break;
  }
  return ierr;
}
