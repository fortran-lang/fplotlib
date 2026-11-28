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
    character, parameter :: NL = achar(10)

    call typeset( &
        "---"//NL// &
        "paper: 5in x 7in"//NL// &
        "margin: 0.55in"//NL// &
        "fontsize: 12pt"//NL// &
        "align: center"//NL// &
        "parskip: 8pt"//NL// &
        "pagecolor: ""#fbf3e4"""//NL// &
        "color: ""#3b2b23"""//NL// &
        "pagenumbers: false"//NL// &
        "valign: center"//NL// &
        "---"//NL//NL// &
        ":::{div}"//NL// &
        ":size: large"//NL// &
        ":italic: true"//NL// &
        ":color: #9a6a3a"//NL// &
        "You are warmly invited to"//NL// &
        ":::"//NL//NL// &
        ":::{div}"//NL// &
        ":size: Huge"//NL// &
        ":weight: bold"//NL// &
        ":color: #8b1a1a"//NL// &
        "Ada’s Fortieth  "//NL// &
        "Birthday Party"//NL// &
        ":::"//NL//NL// &
        ":::{div}"//NL// &
        ":color: #c08a3e"//NL// &
        "$\star \quad \star \quad \star$"//NL// &
        ":::"//NL//NL// &
        "**Saturday, the fourteenth of November**  "//NL// &
        "from seven o’clock in the evening"//NL//NL// &
        "The Old Observatory  "//NL// &
        "42 Starlight Avenue, Los Alamos"//NL//NL// &
        "---"//NL//NL// &
        "Dinner, music and dancing under the stars, and a very short talk on why"//NL// &
        "$e^{i\pi} + 1 = 0$ is the most beautiful equation there is."//NL//NL// &
        ":::{div}"//NL// &
        ":size: small"//NL// &
        ":color: #9a6a3a"//NL// &
        "*Kindly reply by the first of November*  "//NL// &
        "ada@example.org"//NL// &
        ":::"//NL, &
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
