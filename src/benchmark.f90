program benchmark
  use iso_fortran_env
  use iso_c_binding
  use PoisFFT
  implicit none
  
  character(len=256) :: arg
  character(len=256) :: float_precision, use_nonuniform_z_str, out_filename
  integer :: solver_dim
  logical :: use_nonuniform_z
  integer :: measurement_iters, grid_size, grid_size_end, grid_size_step
  integer :: i, argc, bc_count
  integer, allocatable :: BCs(:)
  character(len=1024) :: bc_name
  
  argc = command_argument_count()
  if (argc < 8) then
    write(0,*) "Usage: ./benchmark float_precision solver_dim &
        use_nonuniform_z measurement_iters grid_side_size_begin grid_side_size_end grid_side_size_step out_file BC_1 BC_2 ..."
    stop 1
  end if
  
  call get_command_argument(1, float_precision)
  
  call get_command_argument(2, arg)
  read(arg, *) solver_dim
  
  call get_command_argument(3, use_nonuniform_z_str)
  use_nonuniform_z = (trim(use_nonuniform_z_str) == "true" .or. &
      trim(use_nonuniform_z_str) == "1" .or. trim(use_nonuniform_z_str) == "yes")
  
  call get_command_argument(4, arg)
  read(arg, *) measurement_iters
  
  call get_command_argument(5, arg)
  read(arg, *) grid_size
  
  call get_command_argument(6, arg)
  read(arg, *) grid_size_end
  
  call get_command_argument(7, arg)
  read(arg, *) grid_size_step
  
  call get_command_argument(8, out_filename)
  
  if (argc /= 8 + 2 * solver_dim) then
    write(0,*) "Error: Expected ", 2 * solver_dim, " BC arguments"
    stop 1
  end if
  
  allocate(BCs(2*solver_dim))
  bc_name = ""
  do i = 1, 2*solver_dim
    call get_command_argument(8 + i, arg)
    BCs(i) = ParseBC(trim(arg))
    if (i > 1) bc_name = trim(bc_name) // " "
    bc_name = trim(bc_name) // trim(arg)
  end do
  
  ! First arg is unit - acts as a file handle that we can later
  ! reference when writing
  open(unit=10, file=trim(out_filename), status='replace')
  write(10, '(A)') "dim,precision,solver_type,api,bc_name,grid_size,iteration,total_execution_ms"
  
  if (trim(float_precision) == "float") then
    call run_benchmarks_sp(solver_dim, use_nonuniform_z, measurement_iters, &
        grid_size, grid_size_end, grid_size_step, BCs, trim(bc_name))
  else if (trim(float_precision) == "double") then
    call run_benchmarks_dp(solver_dim, use_nonuniform_z, measurement_iters, &
        grid_size, grid_size_end, grid_size_step, BCs, trim(bc_name))
  else
    write(0,*) "Precision is not 'float' or 'double'"
    stop 1
  end if
  
  close(10)
  
contains

  integer function ParseBC(str)
    character(len=*), intent(in) :: str
    if (str == "P") then
        ParseBC = PoisFFT_PERIODIC
    else if (str == "D") then
        ParseBC = PoisFFT_DIRICHLET
    else if (str == "N") then
        ParseBC = PoisFFT_NEUMANN
    else if (str == "DS") then
        ParseBC = PoisFFT_DIRICHLETSTAG
    else if (str == "NS") then
        ParseBC = PoisFFT_NEUMANNSTAG
    else
      write(0,*) "Unknown BC: ", str
      stop 1
    end if
  end function ParseBC

  subroutine run_benchmarks_dp(dim, use_nonuniform_z, measurement_iters, grid_size, grid_size_end, grid_size_step, BCs, bc_name)
    integer, intent(in) :: dim, measurement_iters, grid_size, grid_size_end, grid_size_step
    logical, intent(in) :: use_nonuniform_z
    integer, intent(in) :: BCs(2*dim)
    character(len=*), intent(in) :: bc_name
    
    integer :: size
    integer :: it
    real(c_double) :: lenx, leny, lenz
    real(c_double), allocatable :: Phi1D(:), RHS1D(:), Phi2D(:,:), RHS2D(:,:), Phi3D(:,:,:), RHS3D(:,:,:), z(:), z_u(:)
    real(c_double) :: p
    integer :: nx, ny, nz
    type(PoisFFT_Solver1D_DP) :: S1
    type(PoisFFT_Solver2D_DP) :: S2
    type(PoisFFT_Solver3D_DP) :: S3
    type(PoisFFT_Solver3D_nonuniform_z_DP) :: S3_nz
    integer(int64) :: t1, t2, count_rate
    real(c_double) :: dt
    integer :: i
    
    lenx = 2.0_c_double * 3.14159265358979323846_c_double
    leny = lenx * 1.1_c_double
    lenz = lenx / 1.1_c_double
    
    call system_clock(count_rate=count_rate)
    
    size = grid_size

    do while(size <= grid_size_end)
      print *, "Measuring grid size ", size
      
      nx = size
      ny = size
      nz = size

      if (dim == 1) then
        allocate(Phi1D(nx))
        allocate(RHS1D(nx))
      else if (dim == 2) then
        allocate(Phi2D(nx, ny))
        allocate(RHS2D(nx, ny))
      else if (dim == 3) then
        allocate(Phi3D(nx, ny, nz))
        allocate(RHS3D(nx, ny, nz))
      endif
      
      if (dim == 1) then
        S1 = PoisFFT_Solver1D_DP([nx], [lenx], BCs)
      else if (dim == 2) then
        S2 = PoisFFT_Solver2D_DP([nx, ny], [lenx, leny], BCs)
      else if (dim == 3) then
        if (use_nonuniform_z) then
          allocate(z(0:nz+1))
          allocate(z_u(-1:nz+1))
          z_u(0:nz) = [(lenz/nz*i, i = 0, nz)]
          do i = 1, nz-1
            call random_number(p)
            p = (p - 0.5_c_double)*0.5_c_double
            z_u(i) = z_u(i) + min(abs(z_u(i+1)-z_u(i)),abs(z_u(i)-z_u(i-1)))*p
          end do
            z_u(-1) = z_u(0) - (z_u(1)-z_u(0))
            z_u(nz+1) = z_u(nz) + (z_u(nz)-z_u(nz-1))
          do i = 0, nz+1
            z(i) = (z_u(i)+z_u(i-1))/2.0_c_double
          end do
          S3_nz = PoisFFT_Solver3D_nonuniform_z_DP([nx,ny,nz], [lenx, leny], z(1:nz), z_u(0:nz), BCs)
        else
          S3 = PoisFFT_Solver3D_DP([nx, ny, nz], [lenx, leny, lenz], BCs)
        end if
      end if
      
      do it = 1, measurement_iters
        print *, "    Iteration ", it-1
        if (dim == 1) then
          call random_number(RHS1D)
          Phi1D = 0.0_c_double
        else if (dim == 2) then
          call random_number(RHS2D)
          Phi2D = 0.0_c_double
        else
          call random_number(RHS3D)
          Phi3D = 0.0_c_double
        end if
        
        call system_clock(t1)
        
        if (dim == 1) then
          call Execute(S1, Phi1D, RHS1D)
        else if (dim == 2) then
          call Execute(S2, Phi2D, RHS2D)
        else if (dim == 3) then
          if (use_nonuniform_z) then
            call Execute(S3_nz, Phi3D, RHS3D)
          else
            call Execute(S3, Phi3D, RHS3D)
          end if
        end if
        
        call system_clock(t2)
        dt = real(t2 - t1, c_double) / real(count_rate, c_double) * 1000.0_c_double
        
        write(10, '(I0,6A,I0,A,I0,A,F15.6)') dim, ",double,", &
             trim(merge("nonuniform_z", "uniform     ", use_nonuniform_z)), ",PoisFFT,", &
             '"', trim(bc_name), '",', size, ',', (it-1), ',', dt
      end do

      if (dim == 1) deallocate(Phi1D, RHS1D)
      if (dim == 2) deallocate(Phi2D, RHS2D)
      if (dim == 3) deallocate(Phi3D, RHS3D)
      
      if (dim == 1) then
        call Finalize(S1)
      else if (dim == 2) then
        call Finalize(S2)
      else if (dim == 3) then
        if (use_nonuniform_z) then
          call Finalize(S3_nz)
          deallocate(z, z_u)
        else
          call Finalize(S3)
        end if
      end if
      
      size = size + grid_size_step
      if (grid_size_step == 0) exit
    end do
  end subroutine

  subroutine run_benchmarks_sp(dim, use_nonuniform_z, measurement_iters, grid_size, grid_size_end, grid_size_step, BCs, bc_name)
    integer, intent(in) :: dim, measurement_iters, grid_size, grid_size_end, grid_size_step
    logical, intent(in) :: use_nonuniform_z
    integer, intent(in) :: BCs(2*dim)
    character(len=*), intent(in) :: bc_name
    
    integer :: size
    integer :: it
    real(c_float) :: lenx, leny, lenz
    real(c_float), allocatable :: Phi1D(:), RHS1D(:), Phi2D(:,:), RHS2D(:,:), Phi3D(:,:,:), RHS3D(:,:,:), z(:), z_u(:)
    real(c_float) :: p
    integer :: nx, ny, nz
    type(PoisFFT_Solver1D_SP) :: S1
    type(PoisFFT_Solver2D_SP) :: S2
    type(PoisFFT_Solver3D_SP) :: S3
    type(PoisFFT_Solver3D_nonuniform_z_SP) :: S3_nz
    integer(int64) :: t1, t2, count_rate
    real(c_double) :: dt
    integer :: i
    
    lenx = 2.0_c_float * 3.14159265358979323846_c_float
    leny = lenx * 1.1_c_float
    lenz = lenx / 1.1_c_float
    
    call system_clock(count_rate=count_rate)
    
    size = grid_size

    do while(size <= grid_size_end)
      print *, "Measuring grid size ", size
      
      nx = size
      ny = size
      nz = size

      if (dim == 1) then
        allocate(Phi1D(nx))
        allocate(RHS1D(nx))
      else if (dim == 2) then
        allocate(Phi2D(nx, ny))
        allocate(RHS2D(nx, ny))
      else if (dim == 3) then
        allocate(Phi3D(nx, ny, nz))
        allocate(RHS3D(nx, ny, nz))
      endif
      
      if (dim == 1) then
        S1 = PoisFFT_Solver1D_SP([nx], [lenx], BCs)
      else if (dim == 2) then
        S2 = PoisFFT_Solver2D_SP([nx, ny], [lenx, leny], BCs)
      else if (dim == 3) then
        if (use_nonuniform_z) then
          allocate(z(0:nz+1))
          allocate(z_u(-1:nz+1))
          z_u(0:nz) = [(lenz/nz*i, i = 0, nz)]
          do i = 1, nz-1
            call random_number(p)
            p = (p - 0.5_c_double)*0.5_c_double
            z_u(i) = z_u(i) + min(abs(z_u(i+1)-z_u(i)),abs(z_u(i)-z_u(i-1)))*p
          end do
            z_u(-1) = z_u(0) - (z_u(1)-z_u(0))
            z_u(nz+1) = z_u(nz) + (z_u(nz)-z_u(nz-1))
          do i = 0, nz+1
            z(i) = (z_u(i)+z_u(i-1))/2.0_c_double
          end do
          S3_nz = PoisFFT_Solver3D_nonuniform_z_SP([nx,ny,nz], [lenx, leny], z(1:nz), z_u(0:nz), BCs)
        else
          S3 = PoisFFT_Solver3D_SP([nx, ny, nz], [lenx, leny, lenz], BCs)
        end if
      end if
      
      do it = 1, measurement_iters
        print *, "    Iteration ", it-1
        if (dim == 1) then
          call random_number(RHS1D)
          Phi1D = 0.0_c_float
        else if (dim == 2) then
          call random_number(RHS2D)
          Phi2D = 0.0_c_float
        else
          call random_number(RHS3D)
          Phi3D = 0.0_c_float
        end if
        
        
        if (dim == 1) then
          call system_clock(t1)
          call Execute(S1, Phi1D, RHS1D)
          call system_clock(t2)
        else if (dim == 2) then
          call system_clock(t1)
          call Execute(S2, Phi2D, RHS2D)
          call system_clock(t2)
        else if (dim == 3) then
          if (use_nonuniform_z) then
            call system_clock(t1)
            call Execute(S3_nz, Phi3D, RHS3D)
            call system_clock(t2)
          else
            call system_clock(t1)
            call Execute(S3, Phi3D, RHS3D)
            call system_clock(t2)
          end if
        end if
        
        dt = real(t2 - t1, c_double) / real(count_rate, c_double) * 1000.0_c_double
        
        write(10, '(I0,6A,I0,A,I0,A,F15.6)') dim, ",float,", &
             trim(merge("nonuniform_z", "uniform     ", use_nonuniform_z)), ",PoisFFT,", &
             '"', trim(bc_name), '",', size, ',', (it-1), ',', dt
      end do

      if (dim == 1) deallocate(Phi1D, RHS1D)
      if (dim == 2) deallocate(Phi2D, RHS2D)
      if (dim == 3) deallocate(Phi3D, RHS3D)
      
      if (dim == 1) then
        call Finalize(S1)
      else if (dim == 2) then
        call Finalize(S2)
      else if (dim == 3) then
        if (use_nonuniform_z) then
          call Finalize(S3_nz)
          deallocate(z, z_u)
        else
          call Finalize(S3)
        end if
      end if
      
      size = size + grid_size_step
      if (grid_size_step == 0) exit
    end do
  end subroutine

end program benchmark
