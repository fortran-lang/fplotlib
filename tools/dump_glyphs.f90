! Dump what fplotlib_glyphs hands out, for tools/check_glyphs.py to compare
! with what tools/gen_glyphs.py --expect says it must. Build it against the
! library and run it from the repository root:
!
!   fpm build --compiler gfortran
!   gfortran -I "$(dirname "$(find build -name fplotlib_glyphs.mod | head -1)")" \
!       tools/dump_glyphs.f90 "$(find build -name libfplotlib.a | head -1)" -o dump_glyphs
!   ./dump_glyphs > glyphs_dump.txt
program dump_glyphs
    use fplotlib_status
    use fplotlib_glyphs
    use fplotlib_style, only: dp
    use fplotlib_resources, only: initialize_resources
    implicit none
    integer :: g, f, i, nv, np, cp, g2, n, c
    integer, allocatable :: v(:), gs(:)
    real(dp), allocatable :: x(:), y(:), ad(:), st(:), en(:), fu(:)
    logical, allocatable :: ex(:)
    real(dp) :: x0, y0, x1, y1, it, k
    character(len=*), parameter :: E = "(es24.16)"

    type(status_t) :: status
    call initialize_resources(status=status)
    call require_ok(status)
    do g = 1, NGLYPH
        call glyph_outline(g, v, nv, x, y, np)
        call glyph_bbox(g, x0, y0, x1, y1)
        write (*, "(a,i0,1x,i0,5(1x,es24.16))") "G ", g, glyph_face(g), glyph_adv(g), &
            x0, y0, x1, y1
        write (*, "(a,*(1x,i0))") "V", v(1:nv)
        write (*, "(a,*(1x,es24.16))") "P", (x(i), y(i), i = 1, np)
        if (glyph_face(g) /= FACE_MATH) cycle
        write (*, "(a,i0,2(1x,es24.16),1x,l1,1x,i0,1x,i0,1x,i0)") "M ", g, &
            glyph_italic(g), glyph_top_accent(g), glyph_extended(g), &
            glyph_ssty(g, 1), glyph_ssty(g, 2), glyph_dotless(g)
        write (*, "(a,i0,*(1x,es24.16))") "K ", g, &
            ((glyph_math_kern(g, c, 0.01_dp*i), i = -50, 150, 5), c = 1, 4)
        do c = 1, 2
            call glyph_variants(g, c == 1, n, gs, ad)
            write (*, "(a,i0,1x,i0,*(1x,i0,1x,es24.16))") "W ", g, c, (gs(i), ad(i), i = 1, n)
            call glyph_assembly(g, c == 1, n, gs, st, en, fu, ex, it)
            write (*, "(a,i0,1x,i0,1x,es24.16,*(1x,i0,3(1x,es24.16),1x,l1))") "A ", g, c, it, &
                (gs(i), st(i), en(i), fu(i), ex(i), i = 1, n)
        end do
    end do
    do f = 1, NFACE
        do cp = 0, 130000
            g = glyph_cmap(f, cp)
            if (g > 0) write (*, "(a,i0,1x,i0,1x,i0)") "C ", f, cp, g
        end do
    end do
    do g = 1, NGLYPH
        f = glyph_face(g)
        do g2 = 1, NGLYPH
            if (glyph_face(g2) /= f) cycle
            k = glyph_kern(f, g, g2)
            if (k /= 0) write (*, "(a,i0,1x,i0,1x,es24.16)") "R ", g, g2, k
        end do
    end do
    write (*, "(a,*(1x,es24.16))") "X", (math_const(i), i = 1, 56)

contains

    subroutine require_ok(status)
        type(status_t), intent(in) :: status
        if (status%ok()) return
        print "(a)", status%message
        error stop 1
    end subroutine require_ok

end program dump_glyphs
