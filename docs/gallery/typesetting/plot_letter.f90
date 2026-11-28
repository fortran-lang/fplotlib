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
    character, parameter :: NL = achar(10)

    call typeset( &
        "---"//NL// &
        "paper: letter"//NL// &
        "fontsize: 11pt"//NL// &
        "margin: 1.1in"//NL// &
        "parskip: 6pt"//NL// &
        "pagenumbers: false"//NL// &
        "signature-skip: 1.2cm"//NL// &
        "---"//NL//NL// &
        ":::{sender}"//NL// &
        "Augusta Ada King, Countess of Lovelace  "//NL// &
        "12 St James’s Square  "//NL// &
        "London"//NL//NL// &
        "10 July 1843"//NL// &
        ":::"//NL//NL// &
        ":::{recipient}"//NL// &
        "Charles Babbage, Esq.  "//NL// &
        "1 Dorset Street  "//NL// &
        "Marylebone, London"//NL// &
        ":::"//NL//NL// &
        "Dear Mr. Babbage,"//NL//NL// &
        "I send you with this letter the translation of General Menabrea’s memoir on"//NL// &
        "the Analytical Engine, together with the notes I have added to it. They have"//NL// &
        "grown, as you will see, to nearly three times the length of the memoir"//NL// &
        "itself; I hope you will not think them too long, for I could not bring"//NL// &
        "myself to leave out anything that seemed to me to bear upon the real nature"//NL// &
        "of the engine."//NL//NL// &
        "In the last of them, Note G, I have worked out in full how the engine might"//NL// &
        "compute the numbers of Bernoulli, $B_n$, from the relation"//NL// &
        "$$ \sum_{k=0}^{n} \binom{n+1}{k} B_k = 0, $$"//NL// &
        "step by step, with every variable and every operation set down in a table."//NL// &
        "I believe it shows better than any general description could that the engine"//NL// &
        "is not a mere calculator of numbers: it may act upon other things besides"//NL// &
        "number, were objects found whose mutual relations could be expressed by"//NL// &
        "those of the abstract science of operations."//NL//NL// &
        "I should be very glad of your corrections before the proofs go back to"//NL// &
        "Mr. Taylor. I shall be in town until the end of the week, and can call upon"//NL// &
        "you at any hour that suits you."//NL//NL// &
        ":::{closing}"//NL// &
        "With kind regards, I remain yours most sincerely,"//NL//NL// &
        "A. A. L."//NL// &
        ":::"//NL, &
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
