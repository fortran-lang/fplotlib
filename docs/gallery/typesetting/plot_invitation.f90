! A party invitation
! ==================
!
! An invitation card, five by seven inches: a coloured page, everything
! centred, type in several sizes and colours, decorative rules, and the
! text centred vertically on the card.
!
! The front matter sets the size of the card, its colour and the colour
! of the text, centres every paragraph (``align: center``), and centres
! the whole on the card (``valign: center``). A ``:::{div}`` takes
! ``:size:``, ``:weight:``, ``:italic:`` and ``:color:``; the size names
! are LaTeX's, from ``small`` to ``Huge``. A backslash at the end of a
! line breaks it.

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
        "Ada’s Fortieth\", &
        "Birthday Party", &
        ":::", &
        "", &
        ":::{div}", &
        ":color: #c08a3e", &
        "$\star \quad \star \quad \star$", &
        ":::", &
        "", &
        "**Saturday, the fourteenth of November**\", &
        "from seven o’clock in the evening", &
        "", &
        "The Old Observatory\", &
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
        "*Kindly reply by the first of November*\", &
        "ada@example.org", &
        ":::"], &
        "invitation.svg")
end program plot_invitation
