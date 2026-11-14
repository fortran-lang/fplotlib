! A party invitation
! ==================
!
! An invitation card, five by seven inches: a coloured page, everything
! centred, type in several sizes and colours, decorative rules, and the
! text centred vertically by the native invitation template.
!
! Standard MyST front matter and document parts carry the content. The
! template sets typography and colors without custom Markdown styling syntax.

program plot_invitation
    use fplotlib, only: markdown, save
    implicit none

    call markdown([character(len=100) :: &
        "---", &
        "title: |", &
        "  Ada’s Fortieth<br>", &
        "  Birthday Party", &
        "exports:", &
        "  - format: pdf", &
        "    template: invitation", &
        "numbering: false", &
        "---", &
        "", &
        "+++ {""part"": ""intro""}", &
        "You are warmly invited to", &
        "", &
        "+++ {""part"": ""ornament""}", &
        "", &
        "$\star \quad \star \quad \star$", &
        "", &
        "+++", &
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
        "+++ {""part"": ""reply""}", &
        "*Kindly reply by the first of November*<br>", &
        "ada@example.org"])
    call save("invitation.svg")
end program plot_invitation
