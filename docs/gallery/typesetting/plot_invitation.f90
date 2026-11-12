! A party invitation
! ==================
!
! An invitation card, five by seven inches: a coloured page, everything
! centred, type in several sizes and colours, decorative rules, and the
! text centred vertically on the card by ``\vspace*{\fill}`` above and
! below it, as in LaTeX.
!
! The front matter sets the size of the card, its colour and the colour
! of the text, and centres every paragraph (``align: center``). Fenced
! divs (``::: {.Huge .bold color=#8b1a1a}``) and bracketed spans
! (``[text]{color=...}``) change the size, weight and colour of what they
! enclose; the size names are LaTeX's, from ``.small`` to ``.Huge``.

program plot_invitation
    use fplotlib, only: typeset
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
        "---", &
        "", &
        "\vspace*{\fill}", &
        "", &
        "::: {.large .italic color=#9a6a3a}", &
        "You are warmly invited to", &
        ":::", &
        "", &
        "::: {.Huge .bold color=#8b1a1a}", &
        "Ada’s Fortieth<br>", &
        "Birthday Party", &
        ":::", &
        "", &
        "[$\star \quad \star \quad \star$]{color=#c08a3e}", &
        "", &
        "**Saturday, the fourteenth of November**<br>", &
        "from seven o’clock in the evening", &
        "", &
        "The Old Observatory<br>", &
        "42 Starlight Avenue, Los Alamos", &
        "", &
        "---", &
        "", &
        "Dinner, music and dancing under the stars, and a very short talk on why", &
        "$e^{i\pi} + 1 = 0$ is the most beautiful equation there is.", &
        "", &
        "::: {.small color=#9a6a3a}", &
        "*Kindly reply by the first of November*<br>", &
        "ada@example.org", &
        ":::", &
        "", &
        "\vspace*{\fill}"], &
        "invitation.svg")
end program plot_invitation
