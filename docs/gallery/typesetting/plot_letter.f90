! A letter
! ========
!
! A formal letter on US letter paper: the sender's address and the date
! set flush right in a fenced div, the recipient's address, the body in
! justified paragraphs separated by space rather than indented, and the
! closing.
!
! The front matter sets the paper, the size of the type, the space
! between paragraphs (``parskip``, which also turns the indentation off)
! and leaves out the page number. ``<br>`` breaks the line there (as does
! a backslash at the end of a line, in Pandoc's Markdown); ``::: right``
! sets what it encloses flush right, as LaTeX's ``flushright`` does.

program plot_letter
    use fplotlib, only: markdown, save
    implicit none

    call markdown([character(len=100) :: &
        "---", &
        "paper: letter", &
        "fontsize: 11pt", &
        "margin: 1.1in", &
        "parskip: 6pt", &
        "pagenumbers: false", &
        "---", &
        "", &
        "::: right", &
        "Augusta Ada King, Countess of Lovelace<br>", &
        "12 St James’s Square<br>", &
        "London", &
        "", &
        "10 July 1843", &
        ":::", &
        "", &
        "Charles Babbage, Esq.<br>", &
        "1 Dorset Street<br>", &
        "Marylebone, London", &
        "", &
        "\bigskip", &
        "", &
        "Dear Mr. Babbage,", &
        "", &
        "I send you with this letter the translation of General Menabrea’s memoir on the", &
        "Analytical Engine, together with the notes I have added to it. They have grown, as", &
        "you will see, to nearly three times the length of the memoir itself; I hope you will", &
        "not think them too long, for I could not bring myself to leave out anything that", &
        "seemed to me to bear upon the real nature of the engine.", &
        "", &
        "In the last of them, Note G, I have worked out in full how the engine might compute", &
        "the numbers of Bernoulli, $B_n$, from the relation", &
        "$$ \sum_{k=0}^{n} \binom{n+1}{k} B_k = 0, $$", &
        "step by step, with every variable and every operation set down in a table. I believe", &
        "it shows better than any general description could that the engine is not a mere", &
        "calculator of numbers: it may act upon other things besides number, were objects found", &
        "whose mutual relations could be expressed by those of the abstract science of", &
        "operations.", &
        "", &
        "I should be very glad of your corrections before the proofs go back to Mr. Taylor. I", &
        "shall be in town until the end of the week, and can call upon you at any hour that", &
        "suits you.", &
        "", &
        "\bigskip", &
        "", &
        "With kind regards, I remain yours most sincerely,", &
        "", &
        "\vspace{1.2cm}", &
        "", &
        "A. A. L."])
    call save("letter.svg")
end program plot_letter
