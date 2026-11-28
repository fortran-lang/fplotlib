! fplotlib_ttf -- pure-Fortran runtime TrueType (.ttf) and OpenType (.otf) loader.
!
! Parses SFNT font files directly into ext_face_t structures consumed by
! fplotlib_glyphs:
!   - SFNT table directory (TrueType 0x00010000/'true' and OpenType CFF 'OTTO')
!   - Required metrics: head, maxp, hhea, hmtx, optional OS/2
!   - Character maps: cmap format 4 (BMP) and format 12 (full Unicode)
!   - Outlines: TrueType loca (short/long) + glyf (simple + composite with 2x2
!     transforms) AND OpenType CFF 1.0 (Type 2 CharStrings -> cubic contours)
!   - Kerning: kern table format 0 (sorted pairs for O(log N) lookup)
!   - Math: optional OpenType MATH table (constants, italics correction, top
!     accent attachment, extended shapes, math kerns, variants and assemblies)
module fplotlib_ttf
    use, intrinsic :: iso_fortran_env, only: int64
    use fplotlib_style, only: dp
    use fplotlib_status, only: status_t, set_status, STATUS_OK, ERROR_IO
    use fplotlib_io, only: read_bytes
    implicit none
    private

    public :: ext_face_t, ext_face_load, ext_face_free, ext_face_copy

    type :: ext_face_t
        logical :: loaded = .false.
        logical :: cubic = .false.
        logical :: has_math = .false.
        integer :: ng = 0
        integer :: em = 1000
        integer :: asc = 800
        integer :: desc = -200
        integer :: xh = 500
        integer :: cap = 700

        ! Per-glyph arrays (1..ng, where 1 is SFNT glyph 0 / .notdef)
        integer, allocatable :: adv(:)
        integer, allocatable :: bbox(:, :)
        integer, allocatable :: gchar(:)
        integer, allocatable :: obeg(:)
        integer, allocatable :: cbeg(:)
        integer, allocatable :: qx(:), qy(:)
        logical, allocatable :: qon(:)
        integer, allocatable :: pbeg(:)
        integer, allocatable :: pg(:)
        ! Composite affine transform per component: [a, b, c, d, dx, dy]
        ! mapping (x, y) -> (a*x + c*y + dx, b*x + d*y + dy)
        real(dp), allocatable :: pmat(:, :)

        ! Sorted cmap: cmcp(1..ncmap) -> cmg(1..ncmap) (local gid 1..ng)
        integer :: ncmap = 0
        integer, allocatable :: cmcp(:), cmg(:)

        ! Sorted pair kerning: key = g1*65536 + g2 -> value in font units
        integer :: nkern = 0
        integer(int64), allocatable :: kern_key(:)
        integer, allocatable :: kern_val(:)

        ! Optional OpenType MATH table
        integer :: math_const(56) = 0
        integer :: min_connector_overlap = 20
        integer, allocatable :: gital(:), gacc(:)
        logical, allocatable :: gext(:)
        integer, allocatable :: mkh0(:, :), mkv0(:, :), mkn(:, :)
        integer, allocatable :: mkh(:), mkv(:)
        integer, allocatable :: cv0(:, :), cvn(:, :), casm(:, :)
        integer, allocatable :: varg(:), vara(:)
        integer, allocatable :: asmi(:), asmp0(:), asmn(:)
        integer, allocatable :: partg(:), partst(:), parten(:), partf(:)
        logical, allocatable :: partx(:)
        integer, allocatable :: ssty(:, :), dtls(:)
    end type ext_face_t

    type :: sfnt_dir_t
        integer :: ntab = 0
        character(len=4), allocatable :: tag(:)
        integer(int64), allocatable :: off(:), length(:)
    end type sfnt_dir_t

    type :: cff_index_t
        integer :: count = 0
        integer(int64), allocatable :: off(:)   ! 1..count+1, absolute 0-based byte offsets
    end type cff_index_t

    type :: int_buf_t
        integer :: n = 0
        integer, allocatable :: a(:)
    end type int_buf_t

    type :: log_buf_t
        integer :: n = 0
        logical, allocatable :: a(:)
    end type log_buf_t

    type :: mat_buf_t
        integer :: n = 0
        real(dp), allocatable :: a(:, :)
    end type mat_buf_t

contains

    subroutine ext_face_free(f)
        type(ext_face_t), intent(inout) :: f
        f%loaded = .false.
        f%cubic = .false.
        f%has_math = .false.
        f%ng = 0
        f%em = 1000
        f%asc = 800
        f%desc = -200
        f%xh = 500
        f%cap = 700
        f%ncmap = 0
        f%nkern = 0
        f%math_const = 0
        f%min_connector_overlap = 20
        if (allocated(f%adv)) deallocate (f%adv)
        if (allocated(f%bbox)) deallocate (f%bbox)
        if (allocated(f%gchar)) deallocate (f%gchar)
        if (allocated(f%obeg)) deallocate (f%obeg)
        if (allocated(f%cbeg)) deallocate (f%cbeg)
        if (allocated(f%qx)) deallocate (f%qx)
        if (allocated(f%qy)) deallocate (f%qy)
        if (allocated(f%qon)) deallocate (f%qon)
        if (allocated(f%pbeg)) deallocate (f%pbeg)
        if (allocated(f%pg)) deallocate (f%pg)
        if (allocated(f%pmat)) deallocate (f%pmat)
        if (allocated(f%cmcp)) deallocate (f%cmcp)
        if (allocated(f%cmg)) deallocate (f%cmg)
        if (allocated(f%kern_key)) deallocate (f%kern_key)
        if (allocated(f%kern_val)) deallocate (f%kern_val)
        if (allocated(f%gital)) deallocate (f%gital)
        if (allocated(f%gacc)) deallocate (f%gacc)
        if (allocated(f%gext)) deallocate (f%gext)
        if (allocated(f%mkh0)) deallocate (f%mkh0)
        if (allocated(f%mkv0)) deallocate (f%mkv0)
        if (allocated(f%mkn)) deallocate (f%mkn)
        if (allocated(f%mkh)) deallocate (f%mkh)
        if (allocated(f%mkv)) deallocate (f%mkv)
        if (allocated(f%cv0)) deallocate (f%cv0)
        if (allocated(f%cvn)) deallocate (f%cvn)
        if (allocated(f%casm)) deallocate (f%casm)
        if (allocated(f%varg)) deallocate (f%varg)
        if (allocated(f%vara)) deallocate (f%vara)
        if (allocated(f%asmi)) deallocate (f%asmi)
        if (allocated(f%asmp0)) deallocate (f%asmp0)
        if (allocated(f%asmn)) deallocate (f%asmn)
        if (allocated(f%partg)) deallocate (f%partg)
        if (allocated(f%partst)) deallocate (f%partst)
        if (allocated(f%parten)) deallocate (f%parten)
        if (allocated(f%partf)) deallocate (f%partf)
        if (allocated(f%partx)) deallocate (f%partx)
        if (allocated(f%ssty)) deallocate (f%ssty)
        if (allocated(f%dtls)) deallocate (f%dtls)
    end subroutine ext_face_free

    subroutine ext_face_copy(src, dst)
        type(ext_face_t), intent(in) :: src
        type(ext_face_t), intent(inout) :: dst
        call ext_face_free(dst)
        dst%loaded = src%loaded
        dst%cubic = src%cubic
        dst%has_math = src%has_math
        dst%ng = src%ng
        dst%em = src%em
        dst%asc = src%asc
        dst%desc = src%desc
        dst%xh = src%xh
        dst%cap = src%cap
        dst%ncmap = src%ncmap
        dst%nkern = src%nkern
        dst%math_const = src%math_const
        dst%min_connector_overlap = src%min_connector_overlap
        call copy_i1(src%adv, dst%adv)
        call copy_i2(src%bbox, dst%bbox)
        call copy_i1(src%gchar, dst%gchar)
        call copy_i1(src%obeg, dst%obeg)
        call copy_i1(src%cbeg, dst%cbeg)
        call copy_i1(src%qx, dst%qx)
        call copy_i1(src%qy, dst%qy)
        call copy_l1(src%qon, dst%qon)
        call copy_i1(src%pbeg, dst%pbeg)
        call copy_i1(src%pg, dst%pg)
        call copy_r2(src%pmat, dst%pmat)
        call copy_i1(src%cmcp, dst%cmcp)
        call copy_i1(src%cmg, dst%cmg)
        call copy_i64(src%kern_key, dst%kern_key)
        call copy_i1(src%kern_val, dst%kern_val)
        call copy_i1(src%gital, dst%gital)
        call copy_i1(src%gacc, dst%gacc)
        call copy_l1(src%gext, dst%gext)
        call copy_i2(src%mkh0, dst%mkh0)
        call copy_i2(src%mkv0, dst%mkv0)
        call copy_i2(src%mkn, dst%mkn)
        call copy_i1(src%mkh, dst%mkh)
        call copy_i1(src%mkv, dst%mkv)
        call copy_i2(src%cv0, dst%cv0)
        call copy_i2(src%cvn, dst%cvn)
        call copy_i2(src%casm, dst%casm)
        call copy_i1(src%varg, dst%varg)
        call copy_i1(src%vara, dst%vara)
        call copy_i1(src%asmi, dst%asmi)
        call copy_i1(src%asmp0, dst%asmp0)
        call copy_i1(src%asmn, dst%asmn)
        call copy_i1(src%partg, dst%partg)
        call copy_i1(src%partst, dst%partst)
        call copy_i1(src%parten, dst%parten)
        call copy_i1(src%partf, dst%partf)
        call copy_l1(src%partx, dst%partx)
        call copy_i2(src%ssty, dst%ssty)
        call copy_i1(src%dtls, dst%dtls)
    end subroutine ext_face_copy

    subroutine copy_i1(s, d)
        integer, allocatable, intent(in) :: s(:)
        integer, allocatable, intent(inout) :: d(:)
        if (allocated(s)) then
            allocate (d(size(s)))
            d = s
        end if
    end subroutine copy_i1

    subroutine copy_i64(s, d)
        integer(int64), allocatable, intent(in) :: s(:)
        integer(int64), allocatable, intent(inout) :: d(:)
        if (allocated(s)) then
            allocate (d(size(s)))
            d = s
        end if
    end subroutine copy_i64

    subroutine copy_i2(s, d)
        integer, allocatable, intent(in) :: s(:, :)
        integer, allocatable, intent(inout) :: d(:, :)
        if (allocated(s)) then
            allocate (d(size(s, 1), size(s, 2)))
            d = s
        end if
    end subroutine copy_i2

    subroutine copy_l1(s, d)
        logical, allocatable, intent(in) :: s(:)
        logical, allocatable, intent(inout) :: d(:)
        if (allocated(s)) then
            allocate (d(size(s)))
            d = s
        end if
    end subroutine copy_l1

    subroutine copy_r2(s, d)
        real(dp), allocatable, intent(in) :: s(:, :)
        real(dp), allocatable, intent(inout) :: d(:, :)
        if (allocated(s)) then
            allocate (d(size(s, 1), size(s, 2)))
            d = s
        end if
    end subroutine copy_r2

    ! --- Safe big-endian byte readers (0-based offsets) ---------------

    pure integer function u8(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        integer :: p
        p = int(off) + 1
        if (p < 1 .or. p > len(raw)) then
            u8 = 0
        else
            u8 = iachar(raw(p:p))
        end if
    end function u8

    pure integer function s8(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        integer :: v
        v = u8(raw, off)
        if (v >= 128) v = v - 256
        s8 = v
    end function s8

    pure integer function u16(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        u16 = u8(raw, off)*256 + u8(raw, off + 1_int64)
    end function u16

    pure integer function i16(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        integer :: v
        v = u16(raw, off)
        if (v >= 32768) v = v - 65536
        i16 = v
    end function i16

    pure integer(int64) function u32(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        u32 = int(u8(raw, off), int64)*16777216_int64 &
              + int(u8(raw, off + 1_int64), int64)*65536_int64 &
              + int(u8(raw, off + 2_int64), int64)*256_int64 &
              + int(u8(raw, off + 3_int64), int64)
    end function u32

    pure integer(int64) function i32(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        integer(int64) :: v
        v = u32(raw, off)
        if (v >= 2147483648_int64) v = v - 4294967296_int64
        i32 = v
    end function i32

    pure real(dp) function f2dot14(raw, off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off
        f2dot14 = real(i16(raw, off), dp)/16384.0_dp
    end function f2dot14

    pure logical function in_bounds(raw, off, n)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: off, n
        in_bounds = off >= 0_int64 .and. n >= 0_int64 &
                    .and. off + n <= int(len(raw), int64)
    end function in_bounds

    ! --- Growable buffer helpers (no LHS reallocation) ----------------

    subroutine ibuf_push(b, v)
        type(int_buf_t), intent(inout) :: b
        integer, intent(in) :: v
        integer, allocatable :: tmp(:)
        integer :: cap
        if (.not. allocated(b%a)) then
            allocate (b%a(64))
            b%n = 0
        else if (b%n >= size(b%a)) then
            cap = max(64, 2*size(b%a))
            allocate (tmp(cap))
            tmp(1:b%n) = b%a(1:b%n)
            call move_alloc(tmp, b%a)
        end if
        b%n = b%n + 1
        b%a(b%n) = v
    end subroutine ibuf_push

    subroutine lbuf_push(b, v)
        type(log_buf_t), intent(inout) :: b
        logical, intent(in) :: v
        logical, allocatable :: tmp(:)
        integer :: cap
        if (.not. allocated(b%a)) then
            allocate (b%a(64))
            b%n = 0
        else if (b%n >= size(b%a)) then
            cap = max(64, 2*size(b%a))
            allocate (tmp(cap))
            tmp(1:b%n) = b%a(1:b%n)
            call move_alloc(tmp, b%a)
        end if
        b%n = b%n + 1
        b%a(b%n) = v
    end subroutine lbuf_push

    subroutine mbuf_push(b, m)
        type(mat_buf_t), intent(inout) :: b
        real(dp), intent(in) :: m(6)
        real(dp), allocatable :: tmp(:, :)
        integer :: cap
        if (.not. allocated(b%a)) then
            allocate (b%a(6, 32))
            b%n = 0
        else if (b%n >= size(b%a, 2)) then
            cap = max(32, 2*size(b%a, 2))
            allocate (tmp(6, cap))
            tmp(:, 1:b%n) = b%a(:, 1:b%n)
            call move_alloc(tmp, b%a)
        end if
        b%n = b%n + 1
        b%a(:, b%n) = m
    end subroutine mbuf_push

    ! --- Main entry point ---------------------------------------------

    subroutine ext_face_load(path, f, status)
        character(len=*), intent(in) :: path
        type(ext_face_t), intent(out) :: f
        type(status_t), intent(out) :: status
        character(len=:), allocatable :: raw
        type(sfnt_dir_t) :: dir
        integer(int64) :: head_off, head_len, maxp_off, maxp_len
        integer(int64) :: hhea_off, hhea_len, hmtx_off, hmtx_len
        integer(int64) :: os2_off, os2_len, cmap_off, cmap_len
        integer(int64) :: loca_off, loca_len, glyf_off, glyf_len
        integer(int64) :: cff_off, cff_len, kern_off, kern_len
        integer(int64) :: math_off, math_len
        integer :: loc_fmt, nhm, g, last_adv, ver
        logical :: has_glyf, has_cff

        call ext_face_free(f)
        call read_bytes(path, raw, status)
        if (.not. status%ok()) return

        call parse_sfnt_dir(raw, dir, status)
        if (.not. status%ok()) return

        ! Required tables: head, maxp, hhea, hmtx, cmap
        if (.not. find_table(dir, "head", head_off, head_len) .or. head_len < 54_int64) then
            call set_status(status, ERROR_IO, "font missing valid 'head' table")
            return
        end if
        if (.not. find_table(dir, "maxp", maxp_off, maxp_len) .or. maxp_len < 6_int64) then
            call set_status(status, ERROR_IO, "font missing valid 'maxp' table")
            return
        end if
        if (.not. find_table(dir, "hhea", hhea_off, hhea_len) .or. hhea_len < 36_int64) then
            call set_status(status, ERROR_IO, "font missing valid 'hhea' table")
            return
        end if
        if (.not. find_table(dir, "hmtx", hmtx_off, hmtx_len)) then
            call set_status(status, ERROR_IO, "font missing 'hmtx' table")
            return
        end if
        if (.not. find_table(dir, "cmap", cmap_off, cmap_len)) then
            call set_status(status, ERROR_IO, "font missing 'cmap' table")
            return
        end if

        f%em = u16(raw, head_off + 18_int64)
        if (f%em <= 0) then
            call set_status(status, ERROR_IO, "font has invalid unitsPerEm")
            return
        end if
        loc_fmt = i16(raw, head_off + 50_int64)
        f%ng = u16(raw, maxp_off + 4_int64)
        if (f%ng <= 0) then
            call set_status(status, ERROR_IO, "font has zero glyphs")
            return
        end if

        f%asc = i16(raw, hhea_off + 4_int64)
        f%desc = i16(raw, hhea_off + 6_int64)
        nhm = u16(raw, hhea_off + 34_int64)
        if (nhm <= 0 .or. int(nhm, int64)*4_int64 > hmtx_len) then
            call set_status(status, ERROR_IO, "font has invalid 'hmtx' table")
            return
        end if

        ! Optional OS/2 metrics
        f%xh = nint(0.5_dp*real(f%em, dp))
        f%cap = max(f%asc, nint(0.7_dp*real(f%em, dp)))
        if (find_table(dir, "OS/2", os2_off, os2_len)) then
            if (os2_len >= 90_int64) then
                ver = u16(raw, os2_off)
                if (ver >= 2) then
                    if (i16(raw, os2_off + 86_int64) > 0) &
                        f%xh = i16(raw, os2_off + 86_int64)
                    if (i16(raw, os2_off + 88_int64) > 0) &
                        f%cap = i16(raw, os2_off + 88_int64)
                end if
            end if
        end if

        ! Horizontal advance widths
        allocate (f%adv(f%ng), f%bbox(4, f%ng), f%gchar(f%ng))
        f%adv = 0
        f%bbox = 0
        f%gchar = 0
        last_adv = 0
        do g = 1, f%ng
            if (g <= nhm) then
                last_adv = u16(raw, hmtx_off + int(g - 1, int64)*4_int64)
            end if
            f%adv(g) = last_adv
        end do

        ! Outlines: TrueType (glyf+loca) or OpenType CFF (CFF )
        has_glyf = find_table(dir, "glyf", glyf_off, glyf_len) .and. &
                   find_table(dir, "loca", loca_off, loca_len)
        has_cff = find_table(dir, "CFF ", cff_off, cff_len)

        if (has_glyf) then
            f%cubic = .false.
            call parse_glyf(raw, loca_off, loca_len, glyf_off, glyf_len, loc_fmt, f, status)
        else if (has_cff) then
            f%cubic = .true.
            call parse_cff(raw, cff_off, cff_len, f, status)
        else
            call set_status(status, ERROR_IO, "font has neither 'glyf' nor 'CFF ' outlines")
            return
        end if
        if (.not. status%ok()) then
            call ext_face_free(f)
            return
        end if

        ! Character map
        call parse_cmap(raw, cmap_off, cmap_len, f, status)
        if (.not. status%ok()) then
            call ext_face_free(f)
            return
        end if

        ! Optional kerning table (format 0)
        if (find_table(dir, "kern", kern_off, kern_len)) then
            call parse_kern(raw, kern_off, kern_len, f)
        end if

        ! Optional OpenType MATH table
        if (find_table(dir, "MATH", math_off, math_len)) then
            call parse_math(raw, math_off, math_len, f)
        end if

        f%loaded = .true.
    end subroutine ext_face_load

    ! --- SFNT directory -----------------------------------------------

    subroutine parse_sfnt_dir(raw, dir, status)
        character(len=*), intent(in) :: raw
        type(sfnt_dir_t), intent(out) :: dir
        type(status_t), intent(out) :: status
        integer(int64) :: ver, rec_off, toff, tlen
        integer :: i, nt
        character(len=4) :: magic

        if (len(raw) < 12) then
            call set_status(status, ERROR_IO, "font file is too short")
            return
        end if
        ver = u32(raw, 0_int64)
        magic = raw(1:4)
        if (ver /= 65536_int64 .and. magic /= "true" .and. magic /= "OTTO") then
            call set_status(status, ERROR_IO, "unsupported font format (expected TTF or OTF)")
            return
        end if
        nt = u16(raw, 4_int64)
        if (nt <= 0 .or. .not. in_bounds(raw, 12_int64, int(nt, int64)*16_int64)) then
            call set_status(status, ERROR_IO, "corrupt SFNT table directory")
            return
        end if
        dir%ntab = nt
        allocate (dir%tag(nt), dir%off(nt), dir%length(nt))
        do i = 1, nt
            rec_off = 12_int64 + int(i - 1, int64)*16_int64
            dir%tag(i) = raw(int(rec_off) + 1:int(rec_off) + 4)
            toff = u32(raw, rec_off + 8_int64)
            tlen = u32(raw, rec_off + 12_int64)
            if (.not. in_bounds(raw, toff, tlen)) then
                call set_status(status, ERROR_IO, "SFNT table out of bounds: "//dir%tag(i))
                return
            end if
            dir%off(i) = toff
            dir%length(i) = tlen
        end do
    end subroutine parse_sfnt_dir

    logical function find_table(dir, tag, off, length)
        type(sfnt_dir_t), intent(in) :: dir
        character(len=4), intent(in) :: tag
        integer(int64), intent(out) :: off, length
        integer :: i
        find_table = .false.
        off = 0_int64
        length = 0_int64
        do i = 1, dir%ntab
            if (dir%tag(i) == tag) then
                off = dir%off(i)
                length = dir%length(i)
                find_table = .true.
                return
            end if
        end do
    end function find_table

    ! --- cmap (Format 4 and Format 12) --------------------------------

    subroutine parse_cmap(raw, cmap_off, cmap_len, f, status)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: cmap_off, cmap_len
        type(ext_face_t), intent(inout) :: f
        type(status_t), intent(out) :: status
        integer :: nt, i, pid, eid, fmt, best_prio, prio
        integer(int64) :: sub_off, best_off, rec
        type(int_buf_t) :: cps, gids

        if (cmap_len < 4_int64) then
            call set_status(status, ERROR_IO, "corrupt 'cmap' header")
            return
        end if
        nt = u16(raw, cmap_off + 2_int64)
        best_prio = 0
        best_off = -1_int64
        do i = 1, nt
            rec = cmap_off + 4_int64 + int(i - 1, int64)*8_int64
            if (.not. in_bounds(raw, rec, 8_int64)) exit
            pid = u16(raw, rec)
            eid = u16(raw, rec + 2_int64)
            sub_off = cmap_off + u32(raw, rec + 4_int64)
            if (.not. in_bounds(raw, sub_off, 2_int64)) cycle
            fmt = u16(raw, sub_off)
            prio = 0
            if (fmt == 12) then
                if (pid == 3 .and. eid == 10) then
                    prio = 100
                else if (pid == 0 .and. (eid == 4 .or. eid == 3)) then
                    prio = 90
                else
                    prio = 70
                end if
            else if (fmt == 4) then
                if (pid == 3 .and. eid == 1) then
                    prio = 50
                else if (pid == 0 .and. (eid == 3 .or. eid == 4)) then
                    prio = 45
                else if (pid == 0) then
                    prio = 40
                else
                    prio = 30
                end if
            end if
            if (prio > best_prio) then
                best_prio = prio
                best_off = sub_off
            end if
        end do

        if (best_off < 0_int64) then
            call set_status(status, ERROR_IO, "no supported 'cmap' subtable (format 4 or 12)")
            return
        end if

        fmt = u16(raw, best_off)
        if (fmt == 12) then
            call parse_cmap_fmt12(raw, best_off, f%ng, cps, gids)
        else
            call parse_cmap_fmt4(raw, best_off, f%ng, cps, gids)
        end if

        call finalize_cmap(cps, gids, f)
    end subroutine parse_cmap

    subroutine parse_cmap_fmt4(raw, st, ng, cps, gids)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: st
        integer, intent(in) :: ng
        type(int_buf_t), intent(inout) :: cps, gids
        integer :: seg2, nseg, i, sc, ec, delta, roff, cp, g
        integer(int64) :: end_arr, start_arr, delta_arr, range_arr, roff_pos, gpos

        if (.not. in_bounds(raw, st, 14_int64)) return
        seg2 = u16(raw, st + 6_int64)
        nseg = seg2/2
        if (nseg <= 0) return
        end_arr = st + 14_int64
        start_arr = end_arr + int(seg2, int64) + 2_int64
        delta_arr = start_arr + int(seg2, int64)
        range_arr = delta_arr + int(seg2, int64)
        if (.not. in_bounds(raw, range_arr, int(seg2, int64))) return

        do i = 0, nseg - 1
            ec = u16(raw, end_arr + int(2*i, int64))
            sc = u16(raw, start_arr + int(2*i, int64))
            delta = i16(raw, delta_arr + int(2*i, int64))
            roff_pos = range_arr + int(2*i, int64)
            roff = u16(raw, roff_pos)
            if (sc == 65535 .and. ec == 65535) cycle
            if (sc > ec) cycle
            do cp = sc, ec
                if (roff == 0) then
                    g = iand(cp + delta + 65536, 65535)
                else
                    gpos = roff_pos + int(roff, int64) + int(2*(cp - sc), int64)
                    if (.not. in_bounds(raw, gpos, 2_int64)) cycle
                    g = u16(raw, gpos)
                    if (g /= 0) g = iand(g + delta + 65536, 65535)
                end if
                if (g > 0 .and. g < ng) then
                    call ibuf_push(cps, cp)
                    call ibuf_push(gids, g + 1)
                end if
            end do
        end do
    end subroutine parse_cmap_fmt4

    subroutine parse_cmap_fmt12(raw, st, ng, cps, gids)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: st
        integer, intent(in) :: ng
        type(int_buf_t), intent(inout) :: cps, gids
        integer(int64) :: ngroups, i, rec, sc, ec, sg, cp, g

        if (.not. in_bounds(raw, st, 16_int64)) return
        ngroups = u32(raw, st + 12_int64)
        if (ngroups <= 0_int64) return
        if (.not. in_bounds(raw, st + 16_int64, ngroups*12_int64)) return

        do i = 0_int64, ngroups - 1_int64
            rec = st + 16_int64 + i*12_int64
            sc = u32(raw, rec)
            ec = u32(raw, rec + 4_int64)
            sg = u32(raw, rec + 8_int64)
            if (sc > ec .or. ec > 1114111_int64) cycle
            do cp = sc, ec
                g = sg + (cp - sc)
                if (g > 0_int64 .and. g < int(ng, int64)) then
                    call ibuf_push(cps, int(cp))
                    call ibuf_push(gids, int(g) + 1)
                end if
            end do
        end do
    end subroutine parse_cmap_fmt12

    subroutine finalize_cmap(cps, gids, f)
        type(int_buf_t), intent(inout) :: cps, gids
        type(ext_face_t), intent(inout) :: f
        integer :: n, i, k, g
        integer, allocatable :: order(:)

        n = cps%n
        if (n <= 0) then
            f%ncmap = 0
            allocate (f%cmcp(0), f%cmg(0))
            return
        end if
        allocate (order(n))
        do i = 1, n
            order(i) = i
        end do
        call sort_i32_idx(cps%a, order, n)

        ! Deduplicate sorted code points
        allocate (f%cmcp(n), f%cmg(n))
        k = 0
        do i = 1, n
            if (k > 0) then
                if (cps%a(order(i)) == f%cmcp(k)) cycle
            end if
            k = k + 1
            f%cmcp(k) = cps%a(order(i))
            g = gids%a(order(i))
            f%cmg(k) = g
            if (g >= 1 .and. g <= f%ng) then
                if (f%gchar(g) == 0) f%gchar(g) = f%cmcp(k)
            end if
        end do
        f%ncmap = k
    end subroutine finalize_cmap

    ! --- TrueType glyf + loca -----------------------------------------

    subroutine parse_glyf(raw, loca_off, loca_len, glyf_off, glyf_len, loc_fmt, f, status)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: loca_off, loca_len, glyf_off, glyf_len
        integer, intent(in) :: loc_fmt
        type(ext_face_t), intent(inout) :: f
        type(status_t), intent(out) :: status
        integer(int64), allocatable :: goff(:)
        integer :: g, ng, nc, total_pts, inst_len, k, fl, rep, x, y, dx, dy
        integer :: cflags, cg, a1, a2, c
        integer(int64) :: p, pos, gend
        integer, allocatable :: end_pts(:), flags(:)
        real(dp) :: mat(6)
        type(int_buf_t) :: cbeg_b, qx_b, qy_b, pg_b
        type(log_buf_t) :: qon_b
        type(mat_buf_t) :: pmat_b

        ng = f%ng
        allocate (goff(ng + 1))
        if (loc_fmt == 0) then
            if (loca_len < int(ng + 1, int64)*2_int64) then
                call set_status(status, ERROR_IO, "corrupt short 'loca' table")
                return
            end if
            do g = 1, ng + 1
                goff(g) = int(u16(raw, loca_off + int(g - 1, int64)*2_int64), int64)*2_int64
            end do
        else if (loc_fmt == 1) then
            if (loca_len < int(ng + 1, int64)*4_int64) then
                call set_status(status, ERROR_IO, "corrupt long 'loca' table")
                return
            end if
            do g = 1, ng + 1
                goff(g) = u32(raw, loca_off + int(g - 1, int64)*4_int64)
            end do
        else
            call set_status(status, ERROR_IO, "unsupported 'loca' format")
            return
        end if

        allocate (f%obeg(ng + 1), f%pbeg(ng + 1))
        call ibuf_push(cbeg_b, 1)

        do g = 1, ng
            f%obeg(g) = cbeg_b%n
            f%pbeg(g) = pg_b%n + 1
            if (goff(g) >= goff(g + 1) .or. goff(g + 1) > glyf_len) cycle
            p = glyf_off + goff(g)
            gend = glyf_off + goff(g + 1)
            if (p + 10_int64 > gend) cycle

            nc = i16(raw, p)
            f%bbox(1, g) = i16(raw, p + 2_int64)
            f%bbox(2, g) = i16(raw, p + 4_int64)
            f%bbox(3, g) = i16(raw, p + 6_int64)
            f%bbox(4, g) = i16(raw, p + 8_int64)

            if (nc > 0) then
                pos = p + 10_int64
                if (pos + int(2*nc + 2, int64) > gend) cycle
                if (allocated(end_pts)) deallocate (end_pts)
                allocate (end_pts(nc))
                do c = 1, nc
                    end_pts(c) = u16(raw, pos + int(2*(c - 1), int64))
                end do
                total_pts = end_pts(nc) + 1
                if (total_pts <= 0) cycle
                inst_len = u16(raw, pos + int(2*nc, int64))
                pos = pos + int(2*nc + 2 + inst_len, int64)
                if (pos > gend) cycle

                if (allocated(flags)) deallocate (flags)
                allocate (flags(total_pts))
                k = 1
                do while (k <= total_pts)
                    if (pos >= gend) exit
                    fl = u8(raw, pos)
                    pos = pos + 1_int64
                    flags(k) = fl
                    k = k + 1
                    if (iand(fl, 8) /= 0 .and. pos < gend) then
                        rep = u8(raw, pos)
                        pos = pos + 1_int64
                        do c = 1, rep
                            if (k > total_pts) exit
                            flags(k) = fl
                            k = k + 1
                        end do
                    end if
                end do
                if (k <= total_pts) cycle

                ! Decode X coordinates
                x = 0
                do k = 1, total_pts
                    fl = flags(k)
                    if (iand(fl, 2) /= 0) then
                        dx = u8(raw, pos)
                        pos = pos + 1_int64
                        if (iand(fl, 16) == 0) dx = -dx
                    else if (iand(fl, 16) /= 0) then
                        dx = 0
                    else
                        dx = i16(raw, pos)
                        pos = pos + 2_int64
                    end if
                    x = x + dx
                    call ibuf_push(qx_b, x)
                    call lbuf_push(qon_b, iand(fl, 1) /= 0)
                end do

                ! Decode Y coordinates
                y = 0
                do k = 1, total_pts
                    fl = flags(k)
                    if (iand(fl, 4) /= 0) then
                        dy = u8(raw, pos)
                        pos = pos + 1_int64
                        if (iand(fl, 32) == 0) dy = -dy
                    else if (iand(fl, 32) /= 0) then
                        dy = 0
                    else
                        dy = i16(raw, pos)
                        pos = pos + 2_int64
                    end if
                    y = y + dy
                    call ibuf_push(qy_b, y)
                end do

                ! Record contour end offsets
                k = qx_b%n - total_pts
                do c = 1, nc
                    call ibuf_push(cbeg_b, k + end_pts(c) + 2)
                end do
            else if (nc < 0) then
                ! Composite glyph
                pos = p + 10_int64
                do
                    if (pos + 4_int64 > gend) exit
                    cflags = u16(raw, pos)
                    cg = u16(raw, pos + 2_int64)
                    pos = pos + 4_int64
                    if (iand(cflags, 1) /= 0) then
                        if (pos + 4_int64 > gend) exit
                        a1 = i16(raw, pos)
                        a2 = i16(raw, pos + 2_int64)
                        pos = pos + 4_int64
                    else
                        if (pos + 2_int64 > gend) exit
                        a1 = s8(raw, pos)
                        a2 = s8(raw, pos + 1_int64)
                        pos = pos + 2_int64
                    end if
                    mat = [1.0_dp, 0.0_dp, 0.0_dp, 1.0_dp, 0.0_dp, 0.0_dp]
                    if (iand(cflags, 2) /= 0) then
                        mat(5) = real(a1, dp)
                        mat(6) = real(a2, dp)
                    end if
                    if (iand(cflags, 8) /= 0) then
                        if (pos + 2_int64 > gend) exit
                        mat(1) = f2dot14(raw, pos)
                        mat(4) = mat(1)
                        pos = pos + 2_int64
                    else if (iand(cflags, 64) /= 0) then
                        if (pos + 4_int64 > gend) exit
                        mat(1) = f2dot14(raw, pos)
                        mat(4) = f2dot14(raw, pos + 2_int64)
                        pos = pos + 4_int64
                    else if (iand(cflags, 128) /= 0) then
                        if (pos + 8_int64 > gend) exit
                        mat(1) = f2dot14(raw, pos)
                        mat(2) = f2dot14(raw, pos + 2_int64)
                        mat(3) = f2dot14(raw, pos + 4_int64)
                        mat(4) = f2dot14(raw, pos + 6_int64)
                        pos = pos + 8_int64
                    end if
                    if (cg >= 0 .and. cg < ng) then
                        call ibuf_push(pg_b, cg + 1)
                        call mbuf_push(pmat_b, mat)
                    end if
                    if (iand(cflags, 32) == 0) exit
                end do
            end if
        end do
        f%obeg(ng + 1) = cbeg_b%n
        f%pbeg(ng + 1) = pg_b%n + 1

        allocate (f%cbeg(cbeg_b%n))
        f%cbeg = cbeg_b%a(1:cbeg_b%n)
        allocate (f%qx(qx_b%n), f%qy(qy_b%n), f%qon(qon_b%n))
        if (qx_b%n > 0) then
            f%qx = qx_b%a(1:qx_b%n)
            f%qy = qy_b%a(1:qy_b%n)
            f%qon = qon_b%a(1:qon_b%n)
        end if
        allocate (f%pg(pg_b%n), f%pmat(6, pg_b%n))
        if (pg_b%n > 0) then
            f%pg = pg_b%a(1:pg_b%n)
            f%pmat = pmat_b%a(:, 1:pg_b%n)
        end if
    end subroutine parse_glyf

    ! --- OpenType CFF 1.0 (Type 2 CharStrings) ------------------------

    subroutine cff_read_index(raw, pos, cff_end, idx, ok)
        character(len=*), intent(in) :: raw
        integer(int64), intent(inout) :: pos
        integer(int64), intent(in) :: cff_end
        type(cff_index_t), intent(out) :: idx
        logical, intent(out) :: ok
        integer :: cnt, osz, i, b
        integer(int64) :: p, v, dbase

        ok = .false.
        idx%count = 0
        if (pos + 2_int64 > cff_end) return
        cnt = u16(raw, pos)
        if (cnt == 0) then
            allocate (idx%off(1))
            idx%off(1) = pos + 2_int64
            pos = pos + 2_int64
            ok = .true.
            return
        end if
        if (pos + 3_int64 > cff_end) return
        osz = u8(raw, pos + 2_int64)
        if (osz < 1 .or. osz > 4) return
        if (pos + 3_int64 + int(cnt + 1, int64)*int(osz, int64) > cff_end) return

        idx%count = cnt
        allocate (idx%off(cnt + 1))
        dbase = pos + 3_int64 + int(cnt + 1, int64)*int(osz, int64) - 1_int64
        p = pos + 3_int64
        do i = 1, cnt + 1
            v = 0_int64
            do b = 1, osz
                v = v*256_int64 + int(u8(raw, p), int64)
                p = p + 1_int64
            end do
            idx%off(i) = dbase + v
            if (idx%off(i) < dbase .or. idx%off(i) > cff_end) return
        end do
        pos = idx%off(cnt + 1)
        ok = .true.
    end subroutine cff_read_index

    subroutine cff_parse_dict(raw, dstart, dend, cs_off, priv_size, priv_off, &
                              subr_off, fdarr_off, fdsel_off)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: dstart, dend
        integer(int64), intent(out) :: cs_off, priv_size, priv_off, subr_off
        integer(int64), intent(out) :: fdarr_off, fdsel_off
        integer(int64) :: pos, val
        integer :: b0, b1, b2, op, sp, nib
        real(dp) :: stk(48)

        cs_off = -1_int64
        priv_size = 0_int64
        priv_off = -1_int64
        subr_off = -1_int64
        fdarr_off = -1_int64
        fdsel_off = -1_int64
        sp = 0
        pos = dstart
        do while (pos < dend)
            b0 = u8(raw, pos)
            pos = pos + 1_int64
            if (b0 <= 21) then
                op = b0
                if (b0 == 12) then
                    if (pos >= dend) exit
                    op = 1200 + u8(raw, pos)
                    pos = pos + 1_int64
                end if
                select case (op)
                case (17)
                    if (sp >= 1) cs_off = nint(stk(1), int64)
                case (18)
                    if (sp >= 2) then
                        priv_size = nint(stk(1), int64)
                        priv_off = nint(stk(2), int64)
                    end if
                case (19)
                    if (sp >= 1) subr_off = nint(stk(1), int64)
                case (1236)
                    if (sp >= 1) fdarr_off = nint(stk(1), int64)
                case (1237)
                    if (sp >= 1) fdsel_off = nint(stk(1), int64)
                end select
                sp = 0
            else if (b0 == 28) then
                val = int(i16(raw, pos), int64)
                pos = pos + 2_int64
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = real(val, dp)
                end if
            else if (b0 == 29) then
                val = i32(raw, pos)
                pos = pos + 4_int64
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = real(val, dp)
                end if
            else if (b0 == 30) then
                ! Real number encoded in nibbles; skip to 0xF terminator
                do while (pos < dend)
                    b1 = u8(raw, pos)
                    pos = pos + 1_int64
                    nib = b1/16
                    if (nib == 15 .or. mod(b1, 16) == 15) exit
                end do
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = 0.0_dp
                end if
            else if (b0 >= 32 .and. b0 <= 246) then
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = real(b0 - 139, dp)
                end if
            else if (b0 >= 247 .and. b0 <= 250) then
                b1 = u8(raw, pos)
                pos = pos + 1_int64
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = real((b0 - 247)*256 + b1 + 108, dp)
                end if
            else if (b0 >= 251 .and. b0 <= 254) then
                b1 = u8(raw, pos)
                pos = pos + 1_int64
                if (sp < 48) then
                    sp = sp + 1
                    stk(sp) = real(-(b0 - 251)*256 - b1 - 108, dp)
                end if
            else
                b2 = b0
            end if
        end do
    end subroutine cff_parse_dict

    subroutine parse_cff(raw, cff_off, cff_len, f, status)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: cff_off, cff_len
        type(ext_face_t), intent(inout) :: f
        type(status_t), intent(out) :: status
        integer :: major, hdr_sz, ng, g, p0, p1
        integer(int64) :: cff_end, pos, cs_off, priv_size, priv_off, subr_off
        integer(int64) :: fdarr_off, fdsel_off, dummy1, dummy2, dummy3, dummy4, dummy5
        type(cff_index_t) :: name_idx, top_idx, str_idx, gsubr_idx, cs_idx, lsubr_idx
        logical :: ok
        type(int_buf_t) :: cbeg_b, qx_b, qy_b
        type(log_buf_t) :: qon_b

        cff_end = cff_off + cff_len
        if (cff_len < 4_int64) then
            call set_status(status, ERROR_IO, "corrupt 'CFF ' header")
            return
        end if
        major = u8(raw, cff_off)
        hdr_sz = u8(raw, cff_off + 2_int64)
        if (major /= 1 .or. cff_off + int(hdr_sz, int64) > cff_end) then
            call set_status(status, ERROR_IO, "unsupported CFF version")
            return
        end if

        pos = cff_off + int(hdr_sz, int64)
        call cff_read_index(raw, pos, cff_end, name_idx, ok)
        if (.not. ok) then
            call set_status(status, ERROR_IO, "corrupt CFF Name INDEX")
            return
        end if
        call cff_read_index(raw, pos, cff_end, top_idx, ok)
        if (.not. ok .or. top_idx%count < 1) then
            call set_status(status, ERROR_IO, "corrupt CFF Top DICT INDEX")
            return
        end if
        call cff_read_index(raw, pos, cff_end, str_idx, ok)
        if (.not. ok) then
            call set_status(status, ERROR_IO, "corrupt CFF String INDEX")
            return
        end if
        call cff_read_index(raw, pos, cff_end, gsubr_idx, ok)
        if (.not. ok) then
            call set_status(status, ERROR_IO, "corrupt CFF Global Subr INDEX")
            return
        end if

        call cff_parse_dict(raw, top_idx%off(1), top_idx%off(2), cs_off, priv_size, &
                            priv_off, subr_off, fdarr_off, fdsel_off)
        if (cs_off < 0_int64 .or. cff_off + cs_off >= cff_end) then
            call set_status(status, ERROR_IO, "CFF missing CharStrings INDEX")
            return
        end if
        pos = cff_off + cs_off
        call cff_read_index(raw, pos, cff_end, cs_idx, ok)
        if (.not. ok) then
            call set_status(status, ERROR_IO, "corrupt CFF CharStrings INDEX")
            return
        end if

        ! Local Subr INDEX from Private DICT (if present)
        lsubr_idx%count = 0
        if (priv_off >= 0_int64 .and. priv_size > 0_int64) then
            if (cff_off + priv_off + priv_size <= cff_end) then
                call cff_parse_dict(raw, cff_off + priv_off, &
                                    cff_off + priv_off + priv_size, &
                                    dummy1, dummy2, dummy3, subr_off, dummy4, dummy5)
                if (subr_off > 0_int64) then
                    if (cff_off + priv_off + subr_off < cff_end) then
                        pos = cff_off + priv_off + subr_off
                        call cff_read_index(raw, pos, cff_end, lsubr_idx, ok)
                    end if
                end if
            end if
        end if

        ng = f%ng
        allocate (f%obeg(ng + 1), f%pbeg(ng + 1))
        f%pbeg = 1
        call ibuf_push(cbeg_b, 1)

        do g = 1, ng
            f%obeg(g) = cbeg_b%n
            p0 = qx_b%n + 1
            if (g <= cs_idx%count) then
                call run_type2_cs(raw, cs_idx%off(g), cs_idx%off(g + 1), &
                                  gsubr_idx, lsubr_idx, cbeg_b, qx_b, qy_b, qon_b)
            end if
            p1 = qx_b%n
            if (p1 >= p0) then
                f%bbox(1, g) = minval(qx_b%a(p0:p1))
                f%bbox(2, g) = minval(qy_b%a(p0:p1))
                f%bbox(3, g) = maxval(qx_b%a(p0:p1))
                f%bbox(4, g) = maxval(qy_b%a(p0:p1))
            end if
        end do
        f%obeg(ng + 1) = cbeg_b%n

        allocate (f%cbeg(cbeg_b%n))
        f%cbeg = cbeg_b%a(1:cbeg_b%n)
        allocate (f%qx(qx_b%n), f%qy(qy_b%n), f%qon(qon_b%n))
        if (qx_b%n > 0) then
            f%qx = qx_b%a(1:qx_b%n)
            f%qy = qy_b%a(1:qy_b%n)
            f%qon = qon_b%a(1:qon_b%n)
        end if
        allocate (f%pg(0), f%pmat(6, 0))
    end subroutine parse_cff

    pure integer function subr_bias(n)
        integer, intent(in) :: n
        if (n < 1240) then
            subr_bias = 107
        else if (n < 33900) then
            subr_bias = 1131
        else
            subr_bias = 32768
        end if
    end function subr_bias

    subroutine run_type2_cs(raw, cs_start, cs_end, gsubr, lsubr, cbeg_b, qx_b, qy_b, qon_b)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: cs_start, cs_end
        type(cff_index_t), intent(in) :: gsubr, lsubr
        type(int_buf_t), intent(inout) :: cbeg_b, qx_b, qy_b
        type(log_buf_t), intent(inout) :: qon_b
        real(dp) :: stk(48), cx, cy
        integer :: sp, nstem, depth, cstart
        logical :: first_op, in_contour, done

        sp = 0
        nstem = 0
        depth = 0
        cx = 0.0_dp
        cy = 0.0_dp
        first_op = .true.
        in_contour = .false.
        done = .false.
        cstart = qx_b%n + 1

        call exec_cs(cs_start, cs_end)
        if (in_contour) call close_contour()

    contains

        subroutine close_contour()
            integer :: npts
            if (.not. in_contour) return
            npts = qx_b%n - cstart + 1
            ! Drop trailing duplicate of start point when on-curve
            if (npts > 1) then
                if (qx_b%a(qx_b%n) == qx_b%a(cstart) .and. &
                    qy_b%a(qx_b%n) == qy_b%a(cstart) .and. qon_b%a(qon_b%n)) then
                    qx_b%n = qx_b%n - 1
                    qy_b%n = qy_b%n - 1
                    qon_b%n = qon_b%n - 1
                    npts = npts - 1
                end if
            end if
            if (npts > 0) then
                call ibuf_push(cbeg_b, qx_b%n + 1)
            end if
            in_contour = .false.
        end subroutine close_contour

        subroutine emit_pt(px, py, on)
            real(dp), intent(in) :: px, py
            logical, intent(in) :: on
            call ibuf_push(qx_b, nint(px))
            call ibuf_push(qy_b, nint(py))
            call lbuf_push(qon_b, on)
        end subroutine emit_pt

        subroutine emit_cubic(dx1, dy1, dx2, dy2, dx3, dy3)
            real(dp), intent(in) :: dx1, dy1, dx2, dy2, dx3, dy3
            real(dp) :: x1, y1, x2, y2, x3, y3
            x1 = cx + dx1
            y1 = cy + dy1
            x2 = x1 + dx2
            y2 = y1 + dy2
            x3 = x2 + dx3
            y3 = y2 + dy3
            call emit_pt(x1, y1, .false.)
            call emit_pt(x2, y2, .false.)
            call emit_pt(x3, y3, .true.)
            cx = x3
            cy = y3
        end subroutine emit_cubic

        recursive subroutine exec_cs(s0, s1)
            integer(int64), intent(in) :: s0, s1
            integer(int64) :: pos
            integer :: b0, b1, op2, i, k, idx, nbytes
            logical :: horiz
            real(dp) :: dx, dy, dx1, dy1, dx2, dy2, dx3, dy3

            pos = s0
            do while (pos < s1 .and. .not. done)
                b0 = u8(raw, pos)
                pos = pos + 1_int64

                if (b0 == 28) then
                    if (pos + 2_int64 > s1) exit
                    if (sp < 48) then
                        sp = sp + 1
                        stk(sp) = real(i16(raw, pos), dp)
                    end if
                    pos = pos + 2_int64
                else if (b0 >= 32 .and. b0 <= 246) then
                    if (sp < 48) then
                        sp = sp + 1
                        stk(sp) = real(b0 - 139, dp)
                    end if
                else if (b0 >= 247 .and. b0 <= 250) then
                    if (pos + 1_int64 > s1) exit
                    b1 = u8(raw, pos)
                    pos = pos + 1_int64
                    if (sp < 48) then
                        sp = sp + 1
                        stk(sp) = real((b0 - 247)*256 + b1 + 108, dp)
                    end if
                else if (b0 >= 251 .and. b0 <= 254) then
                    if (pos + 1_int64 > s1) exit
                    b1 = u8(raw, pos)
                    pos = pos + 1_int64
                    if (sp < 48) then
                        sp = sp + 1
                        stk(sp) = real(-(b0 - 251)*256 - b1 - 108, dp)
                    end if
                else if (b0 == 255) then
                    if (pos + 4_int64 > s1) exit
                    if (sp < 48) then
                        sp = sp + 1
                        stk(sp) = real(i32(raw, pos), dp)/65536.0_dp
                    end if
                    pos = pos + 4_int64
                else
                    select case (b0)
                    case (1, 3, 18, 23)
                        ! hstem, vstem, hstemhm, vstemhm
                        if (first_op .and. mod(sp, 2) == 1) first_op = .false.
                        first_op = .false.
                        nstem = nstem + sp/2
                        sp = 0
                    case (19, 20)
                        ! hintmask, cntrmask
                        if (first_op .and. mod(sp, 2) == 1) first_op = .false.
                        first_op = .false.
                        nstem = nstem + sp/2
                        sp = 0
                        nbytes = (nstem + 7)/8
                        pos = pos + int(nbytes, int64)
                    case (21)
                        ! rmoveto
                        i = 1
                        if (first_op .and. sp > 2) i = 2
                        first_op = .false.
                        if (in_contour) call close_contour()
                        if (sp >= i + 1) then
                            cx = cx + stk(i)
                            cy = cy + stk(i + 1)
                            cstart = qx_b%n + 1
                            in_contour = .true.
                            call emit_pt(cx, cy, .true.)
                        end if
                        sp = 0
                    case (22)
                        ! hmoveto
                        i = 1
                        if (first_op .and. sp > 1) i = 2
                        first_op = .false.
                        if (in_contour) call close_contour()
                        if (sp >= i) then
                            cx = cx + stk(i)
                            cstart = qx_b%n + 1
                            in_contour = .true.
                            call emit_pt(cx, cy, .true.)
                        end if
                        sp = 0
                    case (4)
                        ! vmoveto
                        i = 1
                        if (first_op .and. sp > 1) i = 2
                        first_op = .false.
                        if (in_contour) call close_contour()
                        if (sp >= i) then
                            cy = cy + stk(i)
                            cstart = qx_b%n + 1
                            in_contour = .true.
                            call emit_pt(cx, cy, .true.)
                        end if
                        sp = 0
                    case (5)
                        ! rlineto
                        first_op = .false.
                        i = 1
                        do while (i + 1 <= sp)
                            cx = cx + stk(i)
                            cy = cy + stk(i + 1)
                            call emit_pt(cx, cy, .true.)
                            i = i + 2
                        end do
                        sp = 0
                    case (6, 7)
                        ! hlineto (6) / vlineto (7)
                        first_op = .false.
                        horiz = (b0 == 6)
                        do i = 1, sp
                            if (horiz) then
                                cx = cx + stk(i)
                            else
                                cy = cy + stk(i)
                            end if
                            call emit_pt(cx, cy, .true.)
                            horiz = .not. horiz
                        end do
                        sp = 0
                    case (8)
                        ! rrcurveto
                        first_op = .false.
                        i = 1
                        do while (i + 5 <= sp)
                            call emit_cubic(stk(i), stk(i + 1), stk(i + 2), &
                                            stk(i + 3), stk(i + 4), stk(i + 5))
                            i = i + 6
                        end do
                        sp = 0
                    case (24)
                        ! rcurveline
                        first_op = .false.
                        i = 1
                        do while (i + 5 <= sp - 2)
                            call emit_cubic(stk(i), stk(i + 1), stk(i + 2), &
                                            stk(i + 3), stk(i + 4), stk(i + 5))
                            i = i + 6
                        end do
                        if (i + 1 <= sp) then
                            cx = cx + stk(i)
                            cy = cy + stk(i + 1)
                            call emit_pt(cx, cy, .true.)
                        end if
                        sp = 0
                    case (25)
                        ! rlinecurve
                        first_op = .false.
                        i = 1
                        do while (i + 1 <= sp - 6)
                            cx = cx + stk(i)
                            cy = cy + stk(i + 1)
                            call emit_pt(cx, cy, .true.)
                            i = i + 2
                        end do
                        if (i + 5 <= sp) then
                            call emit_cubic(stk(i), stk(i + 1), stk(i + 2), &
                                            stk(i + 3), stk(i + 4), stk(i + 5))
                        end if
                        sp = 0
                    case (26)
                        ! vvcurveto
                        first_op = .false.
                        i = 1
                        dx1 = 0.0_dp
                        if (mod(sp, 4) == 1) then
                            dx1 = stk(1)
                            i = 2
                        end if
                        do while (i + 3 <= sp)
                            call emit_cubic(dx1, stk(i), stk(i + 1), &
                                            stk(i + 2), 0.0_dp, stk(i + 3))
                            dx1 = 0.0_dp
                            i = i + 4
                        end do
                        sp = 0
                    case (27)
                        ! hhcurveto
                        first_op = .false.
                        i = 1
                        dy1 = 0.0_dp
                        if (mod(sp, 4) == 1) then
                            dy1 = stk(1)
                            i = 2
                        end if
                        do while (i + 3 <= sp)
                            call emit_cubic(stk(i), dy1, stk(i + 1), &
                                            stk(i + 2), stk(i + 3), 0.0_dp)
                            dy1 = 0.0_dp
                            i = i + 4
                        end do
                        sp = 0
                    case (30, 31)
                        ! vhcurveto (30) / hvcurveto (31)
                        first_op = .false.
                        horiz = (b0 == 31)
                        i = 1
                        do while (i + 3 <= sp)
                            k = sp - i + 1
                            if (horiz) then
                                dx1 = stk(i)
                                dy1 = 0.0_dp
                                dx2 = stk(i + 1)
                                dy2 = stk(i + 2)
                                dy3 = stk(i + 3)
                                dx3 = 0.0_dp
                                if (k == 5) then
                                    dx3 = stk(i + 4)
                                    i = i + 5
                                else
                                    i = i + 4
                                end if
                            else
                                dx1 = 0.0_dp
                                dy1 = stk(i)
                                dx2 = stk(i + 1)
                                dy2 = stk(i + 2)
                                dx3 = stk(i + 3)
                                dy3 = 0.0_dp
                                if (k == 5) then
                                    dy3 = stk(i + 4)
                                    i = i + 5
                                else
                                    i = i + 4
                                end if
                            end if
                            call emit_cubic(dx1, dy1, dx2, dy2, dx3, dy3)
                            horiz = .not. horiz
                        end do
                        sp = 0
                    case (10)
                        ! callsubr
                        if (sp >= 1 .and. depth < 10) then
                            idx = nint(stk(sp)) + subr_bias(lsubr%count) + 1
                            sp = sp - 1
                            if (idx >= 1 .and. idx <= lsubr%count) then
                                depth = depth + 1
                                call exec_cs(lsubr%off(idx), lsubr%off(idx + 1))
                                depth = depth - 1
                            end if
                        end if
                    case (29)
                        ! callgsubr
                        if (sp >= 1 .and. depth < 10) then
                            idx = nint(stk(sp)) + subr_bias(gsubr%count) + 1
                            sp = sp - 1
                            if (idx >= 1 .and. idx <= gsubr%count) then
                                depth = depth + 1
                                call exec_cs(gsubr%off(idx), gsubr%off(idx + 1))
                                depth = depth - 1
                            end if
                        end if
                    case (11)
                        ! return
                        return
                    case (14)
                        ! endchar
                        if (in_contour) call close_contour()
                        done = .true.
                        sp = 0
                        return
                    case (12)
                        ! Two-byte escape operator
                        if (pos >= s1) exit
                        op2 = u8(raw, pos)
                        pos = pos + 1_int64
                        first_op = .false.
                        select case (op2)
                        case (34)
                            ! hflex
                            if (sp >= 7) then
                                call emit_cubic(stk(1), 0.0_dp, stk(2), stk(3), stk(4), 0.0_dp)
                                call emit_cubic(stk(5), 0.0_dp, stk(6), -stk(3), stk(7), 0.0_dp)
                            end if
                        case (35)
                            ! flex
                            if (sp >= 12) then
                                call emit_cubic(stk(1), stk(2), stk(3), stk(4), stk(5), stk(6))
                                call emit_cubic(stk(7), stk(8), stk(9), stk(10), stk(11), stk(12))
                            end if
                        case (36)
                            ! hflex1
                            if (sp >= 9) then
                                call emit_cubic(stk(1), stk(2), stk(3), stk(4), stk(5), 0.0_dp)
                                call emit_cubic(stk(6), 0.0_dp, stk(7), stk(8), stk(9), &
                                                -(stk(2) + stk(4) + stk(8)))
                            end if
                        case (37)
                            ! flex1
                            if (sp >= 11) then
                                dx = stk(1) + stk(3) + stk(5) + stk(7) + stk(9)
                                dy = stk(2) + stk(4) + stk(6) + stk(8) + stk(10)
                                call emit_cubic(stk(1), stk(2), stk(3), stk(4), stk(5), stk(6))
                                if (abs(dx) > abs(dy)) then
                                    call emit_cubic(stk(7), stk(8), stk(9), stk(10), stk(11), -dy)
                                else
                                    call emit_cubic(stk(7), stk(8), stk(9), stk(10), -dx, stk(11))
                                end if
                            end if
                        end select
                        sp = 0
                    case default
                        sp = 0
                    end select
                end if
            end do
        end subroutine exec_cs

    end subroutine run_type2_cs

    ! --- kern table (Format 0) ----------------------------------------

    subroutine parse_kern(raw, kern_off, kern_len, f)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: kern_off, kern_len
        type(ext_face_t), intent(inout) :: f
        integer :: ver, ntab, t, cov, fmt, npairs, i, g1, g2, val, k
        integer(int64) :: pos, slen, p, key
        integer(int64), allocatable :: keys(:)
        integer, allocatable :: vals(:), order(:)
        integer :: n, cap

        if (kern_len < 4_int64) return
        ver = u16(raw, kern_off)
        if (ver /= 0) return
        ntab = u16(raw, kern_off + 2_int64)
        pos = kern_off + 4_int64
        n = 0
        cap = 0

        do t = 1, ntab
            if (pos + 6_int64 > kern_off + kern_len) exit
            slen = int(u16(raw, pos + 2_int64), int64)
            cov = u16(raw, pos + 4_int64)
            fmt = cov/256
            if (fmt == 0 .and. iand(cov, 1) /= 0 .and. iand(cov, 6) == 0) then
                if (pos + 14_int64 <= kern_off + kern_len) then
                    npairs = u16(raw, pos + 6_int64)
                    if (n + npairs > cap) then
                        cap = max(npairs, 2*cap + npairs)
                        call grow_kern(keys, vals, n, cap)
                    end if
                    do i = 0, npairs - 1
                        p = pos + 14_int64 + int(i, int64)*6_int64
                        if (p + 6_int64 > kern_off + kern_len) exit
                        g1 = u16(raw, p)
                        g2 = u16(raw, p + 2_int64)
                        val = i16(raw, p + 4_int64)
                        if (val /= 0 .and. g1 < f%ng .and. g2 < f%ng) then
                            n = n + 1
                            keys(n) = int(g1 + 1, int64)*65536_int64 + int(g2 + 1, int64)
                            vals(n) = val
                        end if
                    end do
                end if
            end if
            if (slen <= 0_int64) exit
            pos = pos + slen
        end do

        if (n <= 0) return
        allocate (order(n))
        do i = 1, n
            order(i) = i
        end do
        call sort_i64_idx(keys, order, n)

        allocate (f%kern_key(n), f%kern_val(n))
        k = 0
        do i = 1, n
            key = keys(order(i))
            if (k > 0) then
                if (key == f%kern_key(k)) then
                    f%kern_val(k) = vals(order(i))
                    cycle
                end if
            end if
            k = k + 1
            f%kern_key(k) = key
            f%kern_val(k) = vals(order(i))
        end do
        f%nkern = k
    end subroutine parse_kern

    subroutine grow_kern(keys, vals, n, cap)
        integer(int64), allocatable, intent(inout) :: keys(:)
        integer, allocatable, intent(inout) :: vals(:)
        integer, intent(in) :: n, cap
        integer(int64), allocatable :: tk(:)
        integer, allocatable :: tv(:)
        allocate (tk(cap), tv(cap))
        if (n > 0) then
            tk(1:n) = keys(1:n)
            tv(1:n) = vals(1:n)
        end if
        call move_alloc(tk, keys)
        call move_alloc(tv, vals)
    end subroutine grow_kern

    ! --- OpenType MATH table ------------------------------------------

    subroutine parse_math(raw, math_off, math_len, f)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: math_off, math_len
        type(ext_face_t), intent(inout) :: f
        integer :: maj, c_off, gi_off, mv_off, i, g, ng
        integer(int64) :: p, m_end

        m_end = math_off + math_len
        if (math_len < 10_int64) return
        maj = u16(raw, math_off)
        if (maj /= 1) return
        c_off = u16(raw, math_off + 4_int64)
        gi_off = u16(raw, math_off + 6_int64)
        mv_off = u16(raw, math_off + 8_int64)
        if (c_off == 0) return

        ! 1. MathConstants (214 bytes)
        p = math_off + int(c_off, int64)
        if (p + 214_int64 > m_end) return
        f%math_const(1) = i16(raw, p)
        f%math_const(2) = i16(raw, p + 2_int64)
        f%math_const(3) = u16(raw, p + 4_int64)
        f%math_const(4) = u16(raw, p + 6_int64)
        do i = 5, 55
            f%math_const(i) = i16(raw, p + 8_int64 + int(i - 5, int64)*4_int64)
        end do
        f%math_const(56) = i16(raw, p + 212_int64)

        ng = f%ng
        allocate (f%gital(ng), f%gacc(ng), f%gext(ng))
        allocate (f%mkh0(4, ng), f%mkv0(4, ng), f%mkn(4, ng))
        allocate (f%cv0(2, ng), f%cvn(2, ng), f%casm(2, ng))
        allocate (f%ssty(2, ng), f%dtls(ng))
        f%gital = 0
        do g = 1, ng
            f%gacc(g) = f%adv(g)/2
        end do
        f%gext = .false.
        f%mkh0 = 0
        f%mkv0 = 0
        f%mkn = -1
        f%cv0 = 0
        f%cvn = 0
        f%casm = 0
        f%ssty = 0
        f%dtls = 0

        ! 2. MathGlyphInfo
        if (gi_off > 0) then
            call parse_math_glyph_info(raw, math_off + int(gi_off, int64), m_end, f)
        else
            allocate (f%mkh(0), f%mkv(0))
        end if

        ! 3. MathVariants
        if (mv_off > 0) then
            call parse_math_variants(raw, math_off + int(mv_off, int64), m_end, f)
        else
            allocate (f%varg(0), f%vara(0), f%asmi(0), f%asmp0(0), f%asmn(0))
            allocate (f%partg(0), f%partst(0), f%parten(0), f%partf(0), f%partx(0))
        end if

        f%has_math = .true.
    end subroutine parse_math

    subroutine parse_coverage(raw, cov_off, limit, glyphs, n)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: cov_off, limit
        integer, allocatable, intent(out) :: glyphs(:)
        integer, intent(out) :: n
        integer :: fmt, cnt, i, sg, eg, sc, g, total
        integer(int64) :: rec

        n = 0
        if (cov_off + 4_int64 > limit) then
            allocate (glyphs(0))
            return
        end if
        fmt = u16(raw, cov_off)
        cnt = u16(raw, cov_off + 2_int64)
        if (fmt == 1) then
            if (cov_off + 4_int64 + int(cnt, int64)*2_int64 > limit) then
                allocate (glyphs(0))
                return
            end if
            n = cnt
            allocate (glyphs(n))
            do i = 1, n
                glyphs(i) = u16(raw, cov_off + 4_int64 + int(i - 1, int64)*2_int64) + 1
            end do
        else if (fmt == 2) then
            if (cov_off + 4_int64 + int(cnt, int64)*6_int64 > limit) then
                allocate (glyphs(0))
                return
            end if
            total = 0
            do i = 1, cnt
                rec = cov_off + 4_int64 + int(i - 1, int64)*6_int64
                sg = u16(raw, rec)
                eg = u16(raw, rec + 2_int64)
                sc = u16(raw, rec + 4_int64)
                if (eg >= sg) total = max(total, sc + (eg - sg) + 1)
            end do
            n = total
            allocate (glyphs(n))
            glyphs = 0
            do i = 1, cnt
                rec = cov_off + 4_int64 + int(i - 1, int64)*6_int64
                sg = u16(raw, rec)
                eg = u16(raw, rec + 2_int64)
                sc = u16(raw, rec + 4_int64)
                do g = sg, eg
                    if (sc + (g - sg) + 1 <= n) then
                        glyphs(sc + (g - sg) + 1) = g + 1
                    end if
                end do
            end do
        else
            allocate (glyphs(0))
        end if
    end subroutine parse_coverage

    subroutine parse_math_glyph_info(raw, gi_off, limit, f)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: gi_off, limit
        type(ext_face_t), intent(inout) :: f
        integer :: ic_off, ta_off, ext_off, mk_off, n, i, g, c, koff, hc, j
        integer(int64) :: sub, kp
        integer, allocatable :: cov(:)
        type(int_buf_t) :: mkh_b, mkv_b

        if (gi_off + 8_int64 > limit) then
            allocate (f%mkh(0), f%mkv(0))
            return
        end if
        ic_off = u16(raw, gi_off)
        ta_off = u16(raw, gi_off + 2_int64)
        ext_off = u16(raw, gi_off + 4_int64)
        mk_off = u16(raw, gi_off + 6_int64)

        ! Italics correction
        if (ic_off > 0 .and. gi_off + int(ic_off, int64) + 4_int64 <= limit) then
            sub = gi_off + int(ic_off, int64)
            call parse_coverage(raw, sub + int(u16(raw, sub), int64), limit, cov, n)
            do i = 1, min(n, u16(raw, sub + 2_int64))
                g = cov(i)
                if (g >= 1 .and. g <= f%ng) then
                    f%gital(g) = i16(raw, sub + 4_int64 + int(i - 1, int64)*4_int64)
                end if
            end do
        end if

        ! Top accent attachment
        if (ta_off > 0 .and. gi_off + int(ta_off, int64) + 4_int64 <= limit) then
            sub = gi_off + int(ta_off, int64)
            call parse_coverage(raw, sub + int(u16(raw, sub), int64), limit, cov, n)
            do i = 1, min(n, u16(raw, sub + 2_int64))
                g = cov(i)
                if (g >= 1 .and. g <= f%ng) then
                    f%gacc(g) = i16(raw, sub + 4_int64 + int(i - 1, int64)*4_int64)
                end if
            end do
        end if

        ! Extended shape coverage
        if (ext_off > 0) then
            call parse_coverage(raw, gi_off + int(ext_off, int64), limit, cov, n)
            do i = 1, n
                g = cov(i)
                if (g >= 1 .and. g <= f%ng) f%gext(g) = .true.
            end do
        end if

        ! MathKernInfo
        if (mk_off > 0 .and. gi_off + int(mk_off, int64) + 4_int64 <= limit) then
            sub = gi_off + int(mk_off, int64)
            call parse_coverage(raw, sub + int(u16(raw, sub), int64), limit, cov, n)
            do i = 1, min(n, u16(raw, sub + 2_int64))
                g = cov(i)
                if (g < 1 .or. g > f%ng) cycle
                do c = 1, 4
                    koff = u16(raw, sub + 4_int64 + int(i - 1, int64)*8_int64 &
                               + int(c - 1, int64)*2_int64)
                    if (koff == 0) cycle
                    kp = sub + int(koff, int64)
                    if (kp + 2_int64 > limit) cycle
                    hc = u16(raw, kp)
                    if (kp + 2_int64 + int(2*hc + 1, int64)*4_int64 > limit) cycle
                    f%mkn(c, g) = hc
                    f%mkh0(c, g) = mkh_b%n + 1
                    f%mkv0(c, g) = mkv_b%n + 1
                    do j = 0, hc - 1
                        call ibuf_push(mkh_b, i16(raw, kp + 2_int64 + int(j, int64)*4_int64))
                    end do
                    do j = 0, hc
                        call ibuf_push(mkv_b, i16(raw, kp + 2_int64 + int(hc + j, int64)*4_int64))
                    end do
                end do
            end do
        end if

        allocate (f%mkh(mkh_b%n), f%mkv(mkv_b%n))
        if (mkh_b%n > 0) f%mkh = mkh_b%a(1:mkh_b%n)
        if (mkv_b%n > 0) f%mkv = mkv_b%a(1:mkv_b%n)
    end subroutine parse_math_glyph_info

    subroutine parse_math_variants(raw, mv_off, limit, f)
        character(len=*), intent(in) :: raw
        integer(int64), intent(in) :: mv_off, limit
        type(ext_face_t), intent(inout) :: f
        integer :: vcov_off, hcov_off, vcnt, hcnt, dim, cnt, n, i, g, coff
        integer :: aoff, vcnt_g, j, vg, va, pcnt, pg
        integer(int64) :: list_off, cp, ap, pp
        integer, allocatable :: cov(:)
        type(int_buf_t) :: varg_b, vara_b, asmi_b, asmp0_b, asmn_b
        type(int_buf_t) :: partg_b, partst_b, parten_b, partf_b
        type(log_buf_t) :: partx_b

        if (mv_off + 10_int64 > limit) then
            allocate (f%varg(0), f%vara(0), f%asmi(0), f%asmp0(0), f%asmn(0))
            allocate (f%partg(0), f%partst(0), f%parten(0), f%partf(0), f%partx(0))
            return
        end if
        f%min_connector_overlap = u16(raw, mv_off)
        vcov_off = u16(raw, mv_off + 2_int64)
        hcov_off = u16(raw, mv_off + 4_int64)
        vcnt = u16(raw, mv_off + 6_int64)
        hcnt = u16(raw, mv_off + 8_int64)

        do dim = 1, 2
            if (dim == 1) then
                if (vcov_off == 0 .or. vcnt == 0) cycle
                call parse_coverage(raw, mv_off + int(vcov_off, int64), limit, cov, n)
                cnt = min(n, vcnt)
                list_off = mv_off + 10_int64
            else
                if (hcov_off == 0 .or. hcnt == 0) cycle
                call parse_coverage(raw, mv_off + int(hcov_off, int64), limit, cov, n)
                cnt = min(n, hcnt)
                list_off = mv_off + 10_int64 + int(vcnt, int64)*2_int64
            end if

            do i = 1, cnt
                g = cov(i)
                if (g < 1 .or. g > f%ng) cycle
                if (list_off + int(i, int64)*2_int64 > limit) exit
                coff = u16(raw, list_off + int(i - 1, int64)*2_int64)
                if (coff == 0) cycle
                cp = mv_off + int(coff, int64)
                if (cp + 4_int64 > limit) cycle
                aoff = u16(raw, cp)
                vcnt_g = u16(raw, cp + 2_int64)
                f%cv0(dim, g) = varg_b%n + 1
                f%cvn(dim, g) = 0
                do j = 0, vcnt_g - 1
                    if (cp + 4_int64 + int(j + 1, int64)*4_int64 > limit) exit
                    vg = u16(raw, cp + 4_int64 + int(j, int64)*4_int64) + 1
                    va = u16(raw, cp + 6_int64 + int(j, int64)*4_int64)
                    if (vg >= 1 .and. vg <= f%ng) then
                        call ibuf_push(varg_b, vg)
                        call ibuf_push(vara_b, va)
                        f%cvn(dim, g) = f%cvn(dim, g) + 1
                        if (f%gchar(g) > 0 .and. f%gchar(vg) == 0) f%gchar(vg) = f%gchar(g)
                    end if
                end do
                if (aoff > 0) then
                    ap = cp + int(aoff, int64)
                    if (ap + 6_int64 <= limit) then
                        pcnt = u16(raw, ap + 4_int64)
                        if (pcnt > 0 .and. ap + 6_int64 + int(pcnt, int64)*10_int64 <= limit) then
                            call ibuf_push(asmi_b, i16(raw, ap))
                            call ibuf_push(asmp0_b, partg_b%n + 1)
                            call ibuf_push(asmn_b, pcnt)
                            f%casm(dim, g) = asmi_b%n
                            do j = 0, pcnt - 1
                                pp = ap + 6_int64 + int(j, int64)*10_int64
                                pg = u16(raw, pp) + 1
                                if (pg < 1 .or. pg > f%ng) pg = 1
                                call ibuf_push(partg_b, pg)
                                call ibuf_push(partst_b, u16(raw, pp + 2_int64))
                                call ibuf_push(parten_b, u16(raw, pp + 4_int64))
                                call ibuf_push(partf_b, u16(raw, pp + 6_int64))
                                call lbuf_push(partx_b, iand(u16(raw, pp + 8_int64), 1) /= 0)
                            end do
                        end if
                    end if
                end if
            end do
        end do

        allocate (f%varg(varg_b%n), f%vara(vara_b%n))
        if (varg_b%n > 0) then
            f%varg = varg_b%a(1:varg_b%n)
            f%vara = vara_b%a(1:vara_b%n)
        end if
        allocate (f%asmi(asmi_b%n), f%asmp0(asmp0_b%n), f%asmn(asmn_b%n))
        if (asmi_b%n > 0) then
            f%asmi = asmi_b%a(1:asmi_b%n)
            f%asmp0 = asmp0_b%a(1:asmp0_b%n)
            f%asmn = asmn_b%a(1:asmn_b%n)
        end if
        allocate (f%partg(partg_b%n), f%partst(partst_b%n), f%parten(parten_b%n), &
                  f%partf(partf_b%n), f%partx(partx_b%n))
        if (partg_b%n > 0) then
            f%partg = partg_b%a(1:partg_b%n)
            f%partst = partst_b%a(1:partst_b%n)
            f%parten = parten_b%a(1:parten_b%n)
            f%partf = partf_b%a(1:partf_b%n)
            f%partx = partx_b%a(1:partx_b%n)
        end if
    end subroutine parse_math_variants

    ! --- Heapsort index helpers (O(N log N), zero recursion) -----------

    subroutine sort_i32_idx(a, idx, n)
        integer, intent(in) :: a(:), n
        integer, intent(inout) :: idx(:)
        integer :: i, t
        do i = n/2, 1, -1
            call sift_i32(a, idx, i, n)
        end do
        do i = n, 2, -1
            t = idx(1)
            idx(1) = idx(i)
            idx(i) = t
            call sift_i32(a, idx, 1, i - 1)
        end do
    end subroutine sort_i32_idx

    subroutine sift_i32(a, idx, start, end_)
        integer, intent(in) :: a(:), start, end_
        integer, intent(inout) :: idx(:)
        integer :: root, child, t
        root = start
        do while (2*root <= end_)
            child = 2*root
            if (child + 1 <= end_) then
                if (a(idx(child)) < a(idx(child + 1))) child = child + 1
            end if
            if (a(idx(root)) < a(idx(child))) then
                t = idx(root)
                idx(root) = idx(child)
                idx(child) = t
                root = child
            else
                exit
            end if
        end do
    end subroutine sift_i32

    subroutine sort_i64_idx(a, idx, n)
        integer(int64), intent(in) :: a(:)
        integer, intent(in) :: n
        integer, intent(inout) :: idx(:)
        integer :: i, t
        do i = n/2, 1, -1
            call sift_i64(a, idx, i, n)
        end do
        do i = n, 2, -1
            t = idx(1)
            idx(1) = idx(i)
            idx(i) = t
            call sift_i64(a, idx, 1, i - 1)
        end do
    end subroutine sort_i64_idx

    subroutine sift_i64(a, idx, start, end_)
        integer(int64), intent(in) :: a(:)
        integer, intent(in) :: start, end_
        integer, intent(inout) :: idx(:)
        integer :: root, child, t
        root = start
        do while (2*root <= end_)
            child = 2*root
            if (child + 1 <= end_) then
                if (a(idx(child)) < a(idx(child + 1))) child = child + 1
            end if
            if (a(idx(root)) < a(idx(child))) then
                t = idx(root)
                idx(root) = idx(child)
                idx(child) = t
                root = child
            else
                exit
            end if
        end do
    end subroutine sift_i64

end module fplotlib_ttf
