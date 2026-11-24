! A letter
! ========
!
! A formal letter on US letter paper: the sender's address and the date,
! the recipient's address, the body in justified paragraphs separated by
! space rather than indented, and the closing.
!
! The front matter sets the paper, type size, paragraph skip, and
! ``signature-skip``. The local ``letter_directive`` callback implements
! ``:::{sender}``, ``:::{recipient}`` and ``:::{closing}``.

program plot_letter
    use fplotlib, only: dp, typeset
    use fplotlib_markdown, only: md_document_t, md_ctx_t, md_directive_t, md_blocks, md_meta, &
                                 md_length, md_base_size
    use fplotlib_typeset, only: ts_addvspace, ts_vskip, ts_end_par, ts_glue_t, ALIGN_RIGHT
    implicit none

    call typeset([character(len=100) :: &
        "---", &
        "paper: letter", &
        "fontsize: 11pt", &
        "margin: 1.1in", &
        "parskip: 6pt", &
        "pagenumbers: false", &
        "signature-skip: 1.2cm", &
        "---", &
        "", &
        ":::{sender}", &
        "Augusta Ada King, Countess of Lovelace\ ", &
        "12 St James’s Square\ ", &
        "London", &
        "", &
        "10 July 1843", &
        ":::", &
        "", &
        ":::{recipient}", &
        "Charles Babbage, Esq.\ ", &
        "1 Dorset Street\ ", &
        "Marylebone, London", &
        ":::", &
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
        ":::{closing}", &
        "With kind regards, I remain yours most sincerely,", &
        "", &
        "A. A. L.", &
        ":::"], &
        "letter.svg", on_directive=letter_directive)

contains

    recursive subroutine letter_directive(doc, d, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_directive_t), intent(in) :: d
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        type(md_ctx_t) :: sub
        type(ts_glue_t) :: around, big
        real(dp) :: f, sig
        integer :: p
        character, parameter :: NL = achar(10)

        handled = .true.
        f = md_base_size(doc)/10.0_dp
        around = ts_glue_t(10.0_dp*f, 3.0_dp*f, 5.0_dp*f, 0, 0)
        big = ts_glue_t(12.0_dp*f, 4.0_dp*f, 4.0_dp*f, 0, 0)
        sub = ctx
        select case (d%name)
        case ("sender")
            sub%align = ALIGN_RIGHT
            sub%indent = .false.
            call ts_addvspace(doc%engine, around)
            call md_blocks(doc, d%body, sub)
            call ts_end_par(doc%engine)
            call ts_addvspace(doc%engine, around)
        case ("recipient")
            call md_blocks(doc, d%body, sub)
            call ts_end_par(doc%engine)
            call ts_vskip(doc%engine, big)
        case ("closing")
            call ts_vskip(doc%engine, big)
            sig = md_length(doc, md_meta(doc, "signature-skip"), md_base_size(doc))
            p = index(d%body, NL//NL)
            if (p > 0) then
                call md_blocks(doc, d%body(1:p - 1), sub)
                call ts_vskip(doc%engine, ts_glue_t(sig, 0.0_dp, 0.0_dp, 0, 0))
                call md_blocks(doc, d%body(p + 2:), sub)
            else
                call md_blocks(doc, d%body, sub)
            end if
            call ts_end_par(doc%engine)
        case default
            handled = .false.
        end select
    end subroutine letter_directive

end program plot_letter
