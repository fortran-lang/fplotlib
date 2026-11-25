! A party invitation
! ==================
!
! An invitation card, five by seven inches: a coloured page, everything
! centred, type in several sizes and colours, decorative rules, and the
! text centred vertically on the card.
!
! The front matter sets the card size, colours, and alignment. The local
! ``invitation_body`` callback centres the text vertically on the card,
! as ``valign: center`` asks, and ``invitation_directive`` applies the
! ``:::{div}`` options.

program plot_invitation
    use fplotlib, only: dp, typeset
    use fplotlib_markdown, only: md_document_t, md_ctx_t, md_directive_t, md_blocks, md_option, &
                                 md_color, md_base_size, md_meta
    use fplotlib_typeset, only: ts_vkeep, ts_end_par, ts_glue_t
    implicit none

    call typeset([character(len=100) :: &
        "---", &
        "paper: 5in x 7in", &
        "margin: 0.55in", &
        "fontsize: 12pt", &
        "align: center", &
        "parskip: 8pt", &
        "pagecolor: ""#fbf3e4""", &
        "color: ""#3b2b23""", &
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

    ! valign: center in the front matter puts as much space, \vfill,
    ! before the body as after it.
    recursive subroutine invitation_body(doc, after, ctx)
        type(md_document_t), intent(inout) :: doc
        logical, intent(in) :: after
        type(md_ctx_t), intent(in) :: ctx
        if (md_meta(doc, "valign") == "center") &
            call ts_vkeep(doc%engine, ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 1, 0))
    end subroutine invitation_body

    recursive subroutine invitation_directive(doc, d, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_directive_t), intent(in) :: d
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        type(md_ctx_t) :: sub
        character(len=:), allocatable :: v
        real(dp) :: b

        handled = d%name == "div"
        if (.not. handled) return
        sub = ctx
        b = md_base_size(doc)
        v = md_option(d%opts, "size")
        select case (v)
        case ("small"); sub%size = 0.9_dp*b
        case ("large"); sub%size = 1.2_dp*b
        case ("Huge"); sub%size = 2.488_dp*b
        end select
        if (md_option(d%opts, "weight") == "bold") sub%bold = .true.
        if (md_option(d%opts, "italic") == "true") sub%italic = .true.
        v = md_option(d%opts, "color")
        if (len(v) > 0) sub%color = md_color(v, sub%color)
        call md_blocks(doc, d%body, sub)
        call ts_end_par(doc%engine)
    end subroutine invitation_directive

end program plot_invitation
