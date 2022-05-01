
#include "bcuda_template_private.h"
#include <petscerror.h>

PetscErrorCode C(BuildGPUShell,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
  const msc_t *msc,
  const C(data,LEFT_SUBSPACE)* left_subspace_data,
  const C(data,RIGHT_SUBSPACE)* right_subspace_data,
  Mat *A)
{
  PetscErrorCode ierr;
  int M, N, m, n, mpi_size;
  shell_context *ctx;

  MPI_Comm_size(PETSC_COMM_WORLD, &mpi_size);
  /*
  if (mpi_size > 1) {
    SETERRQ(PETSC_COMM_WORLD, PETSC_ERR_SUP,
      "Shell GPU matrices currently only implemented for 1 MPI process.");
  }
  */

  /* N is dimension of right subspace, M of left */
  M = C(Dim,LEFT_SUBSPACE)(left_subspace_data);
  N = C(Dim,RIGHT_SUBSPACE)(right_subspace_data);

  m = PETSC_DECIDE;
  n = PETSC_DECIDE;
  PetscSplitOwnership(PETSC_COMM_WORLD,&m,&M);
  PetscSplitOwnership(PETSC_COMM_WORLD,&n,&N);

  ierr = C(BuildContext_CUDA,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
    msc, left_subspace_data, right_subspace_data, &ctx);CHKERRQ(ierr);
  
  ierr = MatCreateShell(PETSC_COMM_WORLD, m, n, M, N, ctx, A);CHKERRQ(ierr);

  ierr = MatShellSetOperation(*A, MATOP_MULT,
    (void(*)(void))C(MatMult_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE)));
  ierr = MatShellSetOperation(*A, MATOP_NORM,
    (void(*)(void))C(MatNorm_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE)));
  ierr = MatShellSetOperation(*A, MATOP_CREATE_VECS,
    (void(*)(void))MatCreateVecs_GPU);
  ierr = MatShellSetOperation(*A, MATOP_DESTROY,
    (void(*)(void))C(MatDestroyCtx_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE)));
  return ierr;
}

PetscErrorCode C(BuildContext_CUDA,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
  const msc_t *msc,
  const C(data,LEFT_SUBSPACE)* left_subspace_data,
  const C(data,RIGHT_SUBSPACE)* right_subspace_data,
  shell_context **ctx_p)
{
  PetscErrorCode ierr;
  PetscReal *cpu_real_coeffs, real_part;
  PetscInt nterms, i;
  cudaError_t err;
  shell_context *ctx;

  //ierr = PetscMalloc(sizeof(shell_context), ctx_p);CHKERRQ(ierr);
  ierr = PetscMalloc1(1, ctx_p);CHKERRQ(ierr);
  ctx = (*ctx_p);

  ctx->nmasks = msc->nmasks;
  ctx->nrm = -1;
  nterms = msc->mask_offsets[msc->nmasks];

  // Find the number of local masks
  int mpi_rank, mpi_size;
  MPI_Comm_size(PETSC_COMM_WORLD, &mpi_size);
  int max_msc = pow(2, left_subspace_data->L - log(mpi_size)/log(2));
  //printf("max_msc %d, number of global qubits %d\n", max_msc, int(log(mpi_size)/log(2)));
  int nmasks_local;
  for (nmasks_local = 0; nmasks_local < ctx->nmasks; nmasks_local++) {
      if(msc->masks[nmasks_local] >= max_msc) {
          break;
      }
  }
  ctx->nmasks_local = nmasks_local;
  //printf("number of local masks %d number of total masks %d\n", ctx->nmasks_local, ctx->nmasks);

  MPI_Comm_rank(PETSC_COMM_WORLD, &mpi_rank);
  cudaSetDevice(mpi_rank);

  // Set the scatter context to PETSC_NULL
  ctx->sc_ctx = PETSC_NULL;

  err = cudaMalloc((void **) &(ctx->masks),
    sizeof(PetscInt)*msc->nmasks);CHKERRCUDA(err);
  err = cudaMemcpy(ctx->masks, msc->masks, sizeof(PetscInt)*msc->nmasks,
    cudaMemcpyHostToDevice);CHKERRCUDA(err);

  err = cudaMalloc((void **) &(ctx->mask_offsets),
    sizeof(PetscInt)*(msc->nmasks+1));CHKERRCUDA(err);
  err = cudaMemcpy(ctx->mask_offsets, msc->mask_offsets, sizeof(PetscInt)*(msc->nmasks+1),
    cudaMemcpyHostToDevice);CHKERRCUDA(err);

  err = cudaMalloc((void **) &(ctx->signs), sizeof(PetscInt)*nterms);CHKERRCUDA(err);
  err = cudaMemcpy(ctx->signs, msc->signs, sizeof(PetscInt)*nterms,
    cudaMemcpyHostToDevice);CHKERRCUDA(err);

  err = cudaMalloc((void **) &(ctx->real_coeffs), sizeof(PetscReal)*nterms);CHKERRCUDA(err);
  /*
   * we need a CPU vector in which we will store the real coefficients, then we'll copy
   * from that over to the CPU.
   */
  ierr = PetscMalloc1(nterms, &cpu_real_coeffs);CHKERRQ(ierr);
  for (i=0; i < nterms; ++i) {
    real_part = PetscRealPart(msc->coeffs[i]);
    cpu_real_coeffs[i] = (real_part != 0) ? real_part : PetscImaginaryPart(msc->coeffs[i]);
  }
  err = cudaMemcpy(ctx->real_coeffs, cpu_real_coeffs, sizeof(PetscReal)*nterms,
    cudaMemcpyHostToDevice);CHKERRCUDA(err);
  ierr = PetscFree(cpu_real_coeffs);CHKERRQ(ierr);

  ierr = C(CopySubspaceData_CUDA,LEFT_SUBSPACE)(
    (C(data,LEFT_SUBSPACE)**)&(ctx->left_subspace_data),
    (C(data,LEFT_SUBSPACE)*)left_subspace_data);CHKERRQ(ierr);
  ierr = C(CopySubspaceData_CUDA,RIGHT_SUBSPACE)(
    (C(data,RIGHT_SUBSPACE)**)&(ctx->right_subspace_data),
    (C(data,RIGHT_SUBSPACE)*)right_subspace_data);CHKERRQ(ierr);


  //printf("rank %d, masks %p\n, signs %p\n, offsets %p, real_coeffs %p, nmasks %d\n", mpi_rank, ctx->masks, 
  //ctx->signs, ctx->mask_offsets, ctx->real_coeffs, ctx->nmasks);
  return ierr;
  
}

PetscErrorCode C(MatDestroyCtx_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(Mat A)
{
  PetscErrorCode ierr;
  cudaError_t err;
  shell_context *ctx;
  //PetscAssert(0, PETSC_COMM_WORLD, ierr);
  //printf("mat being destroyed\n");
  ierr = MatShellGetContext(A, &ctx);CHKERRQ(ierr);

  if (ctx->sc_ctx != PETSC_NULL) {
      ierr = VecScatterDestroy(&(ctx->sc_ctx));CHKERRQ(ierr);
      ierr = VecDestroy(&(ctx->x_all));CHKERRQ(ierr);
  }
  
  err = cudaFree(ctx->masks);CHKERRCUDA(err);
  err = cudaFree(ctx->mask_offsets);CHKERRCUDA(err);
  err = cudaFree(ctx->signs);CHKERRCUDA(err);
  err = cudaFree(ctx->real_coeffs);CHKERRCUDA(err);

  ierr = C(DestroySubspaceData_CUDA,LEFT_SUBSPACE)(
    (C(data,LEFT_SUBSPACE)*) ctx->left_subspace_data);CHKERRQ(ierr);
  ierr = C(DestroySubspaceData_CUDA,RIGHT_SUBSPACE)(
    (C(data,RIGHT_SUBSPACE)*) ctx->right_subspace_data);CHKERRQ(ierr);

  ierr = PetscFree(ctx);CHKERRQ(ierr);

  return ierr;
}

PetscErrorCode C(MatMult_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(Mat A, Vec x, Vec b)
{
  PetscErrorCode ierr;
  cudaError_t err;
  shell_context *ctx;

  const PetscScalar* xarray;
  const PetscScalar* x_allarray;
  PetscScalar* barray;
  PetscInt size;

  ierr = MatShellGetContext(A, &ctx);CHKERRQ(ierr);
  
  /* Scatter x to a sequential array */

  // Only do on the first multiplication
  if (ctx->sc_ctx == PETSC_NULL){
    VecScatterCreateToAll(x, &(ctx->sc_ctx), &(ctx->x_all));
  }
  
  VecScatterBegin(ctx->sc_ctx, x, ctx->x_all, INSERT_VALUES, SCATTER_FORWARD);

  ierr = VecSet(b, 0);CHKERRQ(ierr);

  ierr = VecCUDAGetArrayRead(x, &xarray);CHKERRQ(ierr);
  ierr = VecCUDAGetArray(b, &barray);CHKERRQ(ierr);

  ierr = VecGetSize(b, &size);CHKERRQ(ierr);

  err = cudaThreadSynchronize();CHKERRCUDA(err);

  PetscInt row_start, row_end, col_start, col_end;
  int mpi_rank;
  MPI_Comm_rank(PETSC_COMM_WORLD, &mpi_rank);
  ierr = VecGetOwnershipRange(b, &row_start, &row_end);CHKERRQ(ierr);
  ierr = VecGetOwnershipRange(x, &col_start, &col_end);CHKERRQ(ierr);

 C(device_MatMult_local,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))<<<GPU_BLOCK_NUM,GPU_BLOCK_SIZE>>>(
    ctx->masks,
    ctx->mask_offsets,
    ctx->signs,
    ctx->real_coeffs,
    ctx->nmasks_local,
    (C(data,LEFT_SUBSPACE)*) ctx->left_subspace_data,
    (C(data,RIGHT_SUBSPACE)*) ctx->right_subspace_data,
    xarray,
    barray,
    row_start,
    row_end,
    col_start
  );
  err = cudaDeviceSynchronize();CHKERRCUDA(err);

  VecScatterEnd(ctx->sc_ctx, x, ctx->x_all, INSERT_VALUES, SCATTER_FORWARD);
  
  ierr = VecCUDAGetArrayRead(ctx->x_all, &x_allarray);CHKERRQ(ierr);

  /* For Multi-GPU, the data on the device includes 
  - x_allarray
  - row_start
  - row_end
  */

  if (ctx->nmasks - ctx->nmasks_local > 0) {
  C(device_MatMult_global,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))<<<GPU_BLOCK_NUM,GPU_BLOCK_SIZE>>>(
    ctx->masks + ctx->nmasks_local, //starting point for global masks
    ctx->mask_offsets + ctx->nmasks_local, //starting point for global mask offsets
    ctx->signs,
    ctx->real_coeffs,
    ctx->nmasks - ctx->nmasks_local, // number of global masks
    (C(data,LEFT_SUBSPACE)*) ctx->left_subspace_data,
    (C(data,RIGHT_SUBSPACE)*) ctx->right_subspace_data,
    barray,
    x_allarray,
    row_start,
    row_end
  );
  }
  err = cudaDeviceSynchronize();CHKERRCUDA(err);
  MPI_Barrier(PETSC_COMM_WORLD);

  //("rank %d, after the mult\n", mpi_rank);

  ierr = VecCUDARestoreArrayRead(x, &xarray);CHKERRQ(ierr);
  ierr = VecCUDARestoreArrayRead(ctx->x_all, &x_allarray);CHKERRQ(ierr);
  ierr = VecCUDARestoreArray(b, &barray);CHKERRQ(ierr);
  
  //VecScatterDestroy(&sc_ctx);
  //VecDestroy(&x_all);
  return ierr;
}


__global__ void C(device_MatMult_local,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
  PetscInt* masks,
  PetscInt* mask_offsets,
  PetscInt* signs,
  PetscReal* real_coeffs,
  PetscInt nmasks,
  C(data,LEFT_SUBSPACE) *left_subspace_data,
  C(data,RIGHT_SUBSPACE) *right_subspace_data,
  const PetscScalar* xarray,
  PetscScalar* barray,
  PetscInt row_start,
  PetscInt row_end,
  PetscInt col_start)
{
  /* For multi-GPU: 
  /* size -> local_size
     vec_start_index begins with row_start
  */
  /* the following four lines come from the PETSc cuda source */

  PetscInt local_size = row_end - row_start;
  PetscInt entries_per_group = (local_size - 1) / gridDim.x + 1;
  entries_per_group = (entries_per_group == 0) ? 1 : entries_per_group;  // for very small vectors, a group should still do some work
  PetscInt vec_start_index = blockIdx.x * entries_per_group;
  PetscInt vec_stop_index  = PetscMin((blockIdx.x + 1) * entries_per_group, local_size); // don't go beyond vec size

  PetscScalar tmp, val;
  PetscReal sign;
  PetscInt bra, ket, row_idx, col_idx, mask_idx, term_idx, this_start;

#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
  PetscInt s2i_sign;
#endif

//printf("row start %d, local size %d, row_idx + row_start %d, masks %d %d %d , nmasks %d\n", row_start, local_size,
//            row_idx + row_start, masks[0], masks[1], masks[2], nmasks);  

  this_start = vec_start_index + threadIdx.x;
  //printf("row start %d, local size %d, threadIdx.x %d\n", row_start, local_size,
  //        threadIdx.x);
  for (row_idx = this_start; row_idx < vec_stop_index; row_idx += blockDim.x) {

    ket = C(I2S_CUDA,LEFT_SUBSPACE)(row_idx + row_start,left_subspace_data);
    //printf("row start %d, local size %d, row_idx + row_start %d, ket %d\n", row_start, local_size,
     //       row_idx + row_start, ket);
    

    val = 0;
    for (mask_idx = 0; mask_idx < nmasks; ++mask_idx) {
      tmp = 0; //check
      bra = ket^masks[mask_idx];
      /* sum all terms for this matrix element */
      
      for (term_idx = mask_offsets[mask_idx]; term_idx < mask_offsets[mask_idx+1]; ++term_idx) {
#if defined(PETSC_USE_64BIT_INDICES)
        sign = __popcll(bra & signs[term_idx])&1;
#else
        sign = __popc(bra & signs[term_idx])&1;
#endif
        sign = 1 - 2*sign;
        if TERM_REAL_CUDA(masks[mask_idx], signs[term_idx]) {
	  add_real(&tmp, sign * real_coeffs[term_idx]);
        }
        else {
          add_imag(&tmp, sign * real_coeffs[term_idx]);
        }
      }
    
#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
      col_idx = C(S2I_CUDA,RIGHT_SUBSPACE)(bra, &s2i_sign, right_subspace_data);
      tmp *= s2i_sign;
#else
      col_idx = C(S2I_CUDA,RIGHT_SUBSPACE)(bra, right_subspace_data);
#endif
    //("row start %d, local size %d, row_idx + row_start %d, ket %d, col_idx %d\n", row_start, local_size,
    //    row_idx + row_start, ket, col_idx);
      if (col_idx != -1) {
      
	val += tmp * xarray[col_idx - col_start];
      }
    }

#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
    // need to use atomics
    if (right_subspace_data->spinflip) {
      PetscReal* r = (PetscReal *)(&(barray[row_idx]));
      PetscReal* c = r+1;
      atomicAdd(r, val.real());
      atomicAdd(c, val.imag());
    } else {
      barray[row_idx] = val;
    }
#else
    barray[row_idx] = val;
    //printf("updated row_idx %d %d\n", row_idx, row_idx + row_start);
#endif

  }
}


__global__ void C(device_MatMult_global,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
  PetscInt* masks,
  PetscInt* mask_offsets,
  PetscInt* signs,
  PetscReal* real_coeffs,
  PetscInt nmasks,
  C(data,LEFT_SUBSPACE) *left_subspace_data,
  C(data,RIGHT_SUBSPACE) *right_subspace_data,
  PetscScalar* barray,
  const PetscScalar* x_allarray,
  PetscInt row_start,
  PetscInt row_end)
{
  /* For multi-GPU: 
  /* size -> local_size
     vec_start_index begins with row_start
  */
  /* the following four lines come from the PETSc cuda source */

  PetscInt local_size = row_end - row_start;
  PetscInt entries_per_group = (local_size - 1) / gridDim.x + 1;
  entries_per_group = (entries_per_group == 0) ? 1 : entries_per_group;  // for very small vectors, a group should still do some work
  PetscInt vec_start_index = blockIdx.x * entries_per_group;
  PetscInt vec_stop_index  = PetscMin((blockIdx.x + 1) * entries_per_group, local_size); // don't go beyond vec size

  PetscScalar tmp, val;
  PetscReal sign;
  PetscInt bra, ket, row_idx, col_idx, mask_idx, term_idx, this_start;

#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
  PetscInt s2i_sign;
#endif

//printf("row start %d, local size %d, row_idx + row_start %d, masks %d %d %d , nmasks %d\n", row_start, local_size,
//            row_idx + row_start, masks[0], masks[1], masks[2], nmasks);  

  this_start = vec_start_index + threadIdx.x;
  //printf("row start %d, local size %d, threadIdx.x %d\n", row_start, local_size,
  //        threadIdx.x);
  for (row_idx = this_start; row_idx < vec_stop_index; row_idx += blockDim.x) {

    ket = C(I2S_CUDA,LEFT_SUBSPACE)(row_idx + row_start,left_subspace_data);
    //printf("row start %d, local size %d, row_idx + row_start %d, ket %d\n", row_start, local_size,
     //       row_idx + row_start, ket);
    

    val = 0;
    for (mask_idx = 0; mask_idx < nmasks; ++mask_idx) {
      tmp = 0; //check
      bra = ket^masks[mask_idx];
      /* sum all terms for this matrix element */
      
      for (term_idx = mask_offsets[mask_idx]; term_idx < mask_offsets[mask_idx+1]; ++term_idx) {
#if defined(PETSC_USE_64BIT_INDICES)
        sign = __popcll(bra & signs[term_idx])&1;
#else
        sign = __popc(bra & signs[term_idx])&1;
#endif
        sign = 1 - 2*sign;
        if TERM_REAL_CUDA(masks[mask_idx], signs[term_idx]) {
	  add_real(&tmp, sign * real_coeffs[term_idx]);
        }
        else {
          add_imag(&tmp, sign * real_coeffs[term_idx]);
        }
      }
    
#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
      col_idx = C(S2I_CUDA,RIGHT_SUBSPACE)(bra, &s2i_sign, right_subspace_data);
      tmp *= s2i_sign;
#else
      col_idx = C(S2I_CUDA,RIGHT_SUBSPACE)(bra, right_subspace_data);
#endif
    //("row start %d, local size %d, row_idx + row_start %d, ket %d, col_idx %d\n", row_start, local_size,
    //    row_idx + row_start, ket, col_idx);
      if (col_idx != -1) {
      
	val += tmp * x_allarray[col_idx];
      }
    }

#if C(RIGHT_SUBSPACE,SP) == SpinConserve_SP
    // need to use atomics
    if (right_subspace_data->spinflip) {
      PetscReal* r = (PetscReal *)(&(barray[row_idx]));
      PetscReal* c = r+1;
      atomicAdd(r, val.real());
      atomicAdd(c, val.imag());
    } else {
      barray[row_idx] += val;
    }
#else
    barray[row_idx] += val;
    //printf("updated row_idx %d %d\n", row_idx, row_idx + row_start);
#endif

  }
}

PetscErrorCode C(MatNorm_GPU,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(Mat A, NormType type, PetscReal *nrm)
{
  PetscErrorCode ierr;
  cudaError_t err;
  shell_context *ctx;

  PetscReal *d_maxs,*h_maxs;
  PetscInt i, M;

  if (type != NORM_INFINITY) {
    SETERRQ(PETSC_COMM_WORLD,PETSC_ERR_ARG_OUTOFRANGE,"Only NORM_INFINITY is implemented for shell matrices.");
  }

  ierr = MatShellGetContext(A, &ctx);CHKERRQ(ierr);

  /*
    keep the norm cached so we don't have to compute it all the time.
    if we already have it, just return it
  */
  if (ctx->nrm != -1) {
    (*nrm) = ctx->nrm;
    return ierr;
  }

  err = cudaMalloc((void **) &d_maxs, sizeof(PetscReal)*GPU_BLOCK_NUM);CHKERRCUDA(err);
  ierr = PetscMalloc1(GPU_BLOCK_NUM, &h_maxs);CHKERRQ(ierr);

  ierr = MatGetSize(A, &M, NULL);CHKERRQ(ierr);

  C(device_MatNorm,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))<<<GPU_BLOCK_NUM, GPU_BLOCK_SIZE, sizeof(PetscReal)*GPU_BLOCK_SIZE>>>(
    M,
    ctx->masks,
    ctx->mask_offsets,
    ctx->signs,
    ctx->real_coeffs,
    ctx->nmasks,
    (C(data,LEFT_SUBSPACE)*) ctx->left_subspace_data,
    (C(data,RIGHT_SUBSPACE)*) ctx->right_subspace_data,
    d_maxs);

  err = cudaThreadSynchronize();CHKERRCUDA(err);

  err = cudaMemcpy(h_maxs, d_maxs, sizeof(PetscReal)*GPU_BLOCK_NUM, cudaMemcpyDeviceToHost);CHKERRCUDA(err);

  /* now do max of h_maxs */
  (*nrm) = 0;
  for (i = 0; i < GPU_BLOCK_NUM; ++i) {
    if (h_maxs[i] > (*nrm)) (*nrm) = h_maxs[i];
  }

  ctx->nrm = (*nrm);

  err = cudaFree(d_maxs);CHKERRCUDA(err);
  ierr = PetscFree(h_maxs);CHKERRQ(ierr);

  return ierr;
}

__global__ void C(device_MatNorm,C(LEFT_SUBSPACE,RIGHT_SUBSPACE))(
  PetscInt size,
  PetscInt* masks,
  PetscInt* mask_offsets,
  PetscInt* signs,
  PetscReal* real_coeffs,
  PetscInt nmasks,
  C(data,LEFT_SUBSPACE) *left_subspace_data,
  C(data,RIGHT_SUBSPACE) *right_subspace_data,
  PetscReal *d_maxs)
{
  extern __shared__ PetscReal threadmax[];

  /* the following four lines come from the PETSc cuda source */
  PetscInt entries_per_group = (size - 1) / gridDim.x + 1;
  entries_per_group = (entries_per_group == 0) ? 1 : entries_per_group;  // for very small vectors, a group should still do some work
  PetscInt vec_start_index = blockIdx.x * entries_per_group;
  PetscInt vec_stop_index  = PetscMin((blockIdx.x + 1) * entries_per_group, size); // don't go beyond vec size

  PetscReal sum,v1,v2,sign;
  PetscScalar csum;
  PetscInt ket, bra, row_idx, mask_idx, term_idx, i;

  /* first find this thread's max and put it in threadmax */

  threadmax[threadIdx.x] = 0;
  for (row_idx = vec_start_index+threadIdx.x; row_idx < vec_stop_index; row_idx += blockDim.x) {
    ket = C(I2S_CUDA,LEFT_SUBSPACE)(row_idx,left_subspace_data);
    sum = 0;
    for (mask_idx = 0; mask_idx < nmasks; ++mask_idx) {
      csum = 0;
      bra = ket ^ masks[mask_idx];
      /* sum all terms for this matrix element */
      for (term_idx = mask_offsets[mask_idx]; term_idx < mask_offsets[mask_idx+1]; ++term_idx) {
#if defined(PETSC_USE_64BIT_INDICES)
        sign = __popcll(bra & signs[term_idx])&1;
#else
        sign = __popc(bra & signs[term_idx])&1;
#endif
        sign = 1 - 2*sign;
        if TERM_REAL_CUDA(masks[mask_idx], signs[term_idx]) {
	  add_real(&csum, sign * real_coeffs[term_idx]);
        }
        else {
          add_imag(&csum, sign * real_coeffs[term_idx]);
        }
      }
      sum += abs(csum);
    }
    if (sum > threadmax[threadIdx.x]) {
      threadmax[threadIdx.x] = sum;
    }
  }
  __syncthreads();

  /* now do the coolest reduce ever on the shared memory and hand it off to CPU */

  for (i=1; i<blockDim.x; i*=2) {
    if (threadIdx.x % (2*i) == 0) {
      v1 = threadmax[threadIdx.x];
      v2 = threadmax[threadIdx.x + i];
      threadmax[threadIdx.x] = v1>v2 ? v1 : v2;
    }
    __syncthreads();
  }

  if (threadIdx.x == 0) d_maxs[blockIdx.x] = threadmax[0];
}
