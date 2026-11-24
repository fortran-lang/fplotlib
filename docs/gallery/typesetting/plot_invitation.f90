! A party invitation
! ==================
!
! An invitation card, five by seven inches: a coloured page, everything
! centred, type in several sizes and colours, decorative rules, and the
! text centred vertically on the card.
!
! The front matter sets the card size, colours, and alignment. The local
! ``invitation_body`` and ``invitation_directive`` callbacks centre the
! text vertically on the card and apply ``:::{div}`` options.

program plot_invitation
    use fplotlib, only: dp, typeset
    use fplotlib_markdown, only: md_ctx_t, md_blocks, md_option, md_color, md_base_size
    use fplotlib_typeset, only: ts_vkeep, ts_end_par, ts_glue_t
    implicit none

    call typeset([character(len=100) :: &
        "---", &
        "paper: 5in x 7in", &
        "margin: 0.55in", &
        "fontsize: 12pt", &
        "align: center", &
        "parskip: 8pt", &
        "pagecolor: #fbf3e4", &
        "color: #3b2b23", &
        "pagenumbers: false", &
        "valign: center", &
        "---", &
        "", &
        ":::{div}", &
        ":size: large", &
        ":italic: true", &
        ":color: #9a6a3a", &
        "You are warmly invited to", &
        ":::", &
        "", &
        ":::{div}", &
        ":size: Huge", &
        ":weight: bold", &
        ":color: #8b1a1a", &
        "Ada’s Fortieth\ ", &
        "Birthday Party", &
        ":::", &
        "", &
        ":::{div}", &
        ":color: #c08a3e", &
        "$\star \quad \star \quad \star$", &
        ":::", &
        "", &
        "**Saturday, the fourteenth of November**\ ", &
        "from seven o’clock in the evening", &
        "", &
        "The Old Observatory\ ", &
        "42 Starlight Avenue, Los Alamos", &
        "", &
        "---", &
        "", &
        "Dinner, music and dancing under the stars, and a very short talk on why", &
        "$e^{i\pi} + 1 = 0$ is the most beautiful equation there is.", &
        "", &
        ":::{div}", &
        ":size: small", &
        ":color: #9a6a3a", &
        "*Kindly reply by the first of November*\ ", &
        "ada@example.org", &
        ":::"], &
        "invitation.svg", on_directive=invitation_directive, on_body=invitation_body)

contains

    subroutine invitation_body(after, ctx)
        logical, intent(in) :: after
        type(md_ctx_t), intent(in) :: ctx
        if (after .or. ctx%size > 0.0_dp) call ts_vkeep(ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0))
    end subroutine invitation_body

    subroutine invitation_directive(name, opts, body, ctx)
        character(len=*), intent(in) :: name, opts, body
        type(md_ctx_t), intent(in) :: ctx
        type(md_ctx_t) :: sub
        character(len=:), allocatable :: v
        real(dp) :: b

        sub = ctx
        b = md_base_size()
        if (name == "div") then
            v = md_option(opts, "size")
            select case (v)
            case ("small"); sub%size = 0.9_dp*b
            case ("large"); sub%size = 1.2_dp*b
            case ("Huge"); sub%size = 2.488_dp*b
            end select
            if (md_option(opts, "weight") == "bold") sub%bold = .true.
            if (md_option(opts, "italic") == "true") sub%italic = .true.
            v = md_option(opts, "color")
            if (len(v) > 0) sub%color = md_color(v, sub%color)
        end if
        call md_blocks(body, sub)
        call ts_end_par()
    end subroutine invitation_directive

end program plot_invitation
