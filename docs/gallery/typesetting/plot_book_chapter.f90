! A book chapter
! ==============
!
! The opening of a chapter of a book, on A5 paper: LaTeX's book class
! sets the chapter heading on a new page, "Chapter 1" above the title,
! numbers the sections and the equations within the chapter, and puts a
! running head and the page number at the top of every page after the
! first. Pages are filled to the bottom (``\flushbottom``) by stretching
! the space between paragraphs, as a book's pages are.
!
! ``chapters: true``, ``runningheads: true`` and ``flushbottom: true``
! configure the book layout, and the local ``book_heading`` callback sets
! chapter openings and running heads.

program plot_book_chapter
    use fplotlib, only: dp, typeset
    use fplotlib_markdown, only: md_document_t, md_ctx_t, md_heading_t, md_inline, md_noindent, &
                                 md_base_size
    use fplotlib_typeset, only: ts_page_break, ts_mark, ts_vkeep, ts_begin_par, &
                                ts_end_par, ts_penalty, ts_vskip, ts_nobreak_next, &
                                ts_glue_t, ALIGN_LEFT
    implicit none
    character, parameter :: NL = achar(10)

    call typeset( &
        "---"//NL// &
        "chapters: true"//NL// &
        "runningheads: true"//NL// &
        "flushbottom: true"//NL// &
        "paper: a5"//NL// &
        "fontsize: 10pt"//NL// &
        "margin: 1.8cm"//NL// &
        "margin-top: 2.2cm"//NL// &
        "numbersections: true"//NL// &
        "---"//NL//NL// &
        "# The Shape of a Paragraph"//NL//NL// &
        "> *Typography exists to honor content.*\"//NL// &
        "> --- Robert Bringhurst"//NL//NL// &
        "When Donald Knuth received the galley proofs of the second edition of his"//NL// &
        "book on algorithms in 1977, he was dismayed. The publisher had replaced its"//NL// &
        "hot-metal type, set by hand, with an early phototypesetting system, and the"//NL// &
        "pages looked wrong to him: the spacing was uneven, the mathematics poorly"//NL// &
        "arranged. He decided to write a program that would set his books as well as"//NL// &
        "the best printers of the past had done, and expected the work to take him a"//NL// &
        "few months. It took him ten years, and the result, TeX, is still in daily"//NL// &
        "use."//NL//NL// &
        "This chapter describes three of the ideas that make TeX’s pages look the way"//NL// &
        "they do: how it decides where to break the lines of a paragraph, where to"//NL// &
        "hyphenate a word, and where to end a page."//NL//NL// &
        "## Boxes, glue and penalties"//NL//NL// &
        "TeX sees a paragraph as a sequence of *boxes*, which are the characters and"//NL// &
        "anything else of a fixed size, separated by *glue*, which is space that may"//NL// &
        "stretch or shrink, and *penalties*, which mark the places where a line may"//NL// &
        "be broken and say how undesirable a break there would be. A line is good"//NL// &
        "when its glue has to stretch or shrink little to fill the measure; TeX"//NL// &
        "measures this by the *badness*"//NL// &
        "$$ b = 100\,r^3, $$ (eq:badness)"//NL// &
        "where $r$ is the ratio of the stretching or shrinking needed to the amount"//NL// &
        "available. A line whose glue is stretched to its full stretchability has a"//NL// &
        "badness of 100, and TeX’s default tolerance of 200 allows a little more than"//NL// &
        "that."//NL//NL// &
        "Each line is then given a number of *demerits*, which grows with its badness"//NL// &
        "and with the penalty $p$ of the break at its end,"//NL// &
        "$$ d = (l + b)^2 + p^2, $$ (eq:demerits)"//NL// &
        "$l$ being a small penalty for every line, so that a paragraph of fewer lines"//NL// &
        "is preferred. Further demerits are added when two consecutive lines end with"//NL// &
        "hyphens, or when a very loose line follows a very tight one."//NL//NL// &
        "## The best breaks"//NL//NL// &
        "Most programs break a paragraph one line at a time: they put as many words"//NL// &
        "as fit on the first line, and then go on to the next. Knuth and Plass"//NL// &
        "instead considered the paragraph as a whole. Among all the ways of breaking"//NL// &
        "it into lines, their algorithm finds the one whose total demerits, the sum"//NL// &
        "of {eq}`eq:demerits` over all its lines, are the smallest. A decision taken"//NL// &
        "early in the paragraph can therefore make the spacing of a line near its end"//NL// &
        "better, and a single long word does not spoil the lines before it."//NL//NL// &
        "The number of ways of breaking a paragraph grows exponentially with its"//NL// &
        "length, but the algorithm need not look at most of them. It walks through"//NL// &
        "the paragraph once and keeps, at each possible break, only the best way of"//NL// &
        "reaching it: the best way of breaking what comes before a break does not"//NL// &
        "depend on what comes after it. This is dynamic programming, and it makes the"//NL// &
        "work grow only in proportion to the length of the paragraph."//NL//NL// &
        "## Hyphenation"//NL//NL// &
        "When a paragraph cannot be broken well, TeX tries again, this time allowing"//NL// &
        "words to be hyphenated. It finds the places where a word may be divided with"//NL// &
        "a method devised by Frank Liang, Knuth’s student: a few thousand short"//NL// &
        "patterns, learned from a dictionary, which say whether a hyphen is allowed"//NL// &
        "or forbidden between two letters in a given context. The patterns are small,"//NL// &
        "and they find nearly nine words in ten that a dictionary would hyphenate,"//NL// &
        "with almost no false hyphens."//NL//NL// &
        "## Pages"//NL//NL// &
        "Pages are made in much the same way as lines. The lines of the paragraphs,"//NL// &
        "the space between them and the penalties for breaking a page between them"//NL// &
        "form a vertical list, and TeX cuts it into pages, choosing for each page the"//NL// &
        "break of least cost: a page that has to be stretched or shrunk a great deal"//NL// &
        "costs much, a break that leaves a single line of a paragraph at the top or"//NL// &
        "bottom of a page, a widow or an orphan, costs a penalty. Unlike the lines of"//NL// &
        "a paragraph, pages are chosen one at a time, since a page has to be output"//NL// &
        "before the next can be begun."//NL, &
        "chapter.svg", on_heading=book_heading)

contains

    recursive subroutine book_heading(doc, h, ctx, handled)
        type(md_document_t), intent(inout) :: doc
        type(md_heading_t), intent(in) :: h
        type(md_ctx_t), intent(in) :: ctx
        logical, intent(inout) :: handled
        type(md_ctx_t) :: sub
        real(dp) :: b

        if (h%level == 2) then
            if (len(h%num) > 0) then
                call ts_mark(doc%engine, upcase(h%num//".  "//h%text), .false., section=.true.)
            else
                call ts_mark(doc%engine, upcase(h%text), .false., section=.true.)
            end if
            return
        end if
        if (h%level /= 1) return
        handled = .true.
        b = md_base_size(doc)
        call ts_page_break(doc%engine)
        if (len(h%num) > 0) then
            call ts_mark(doc%engine, upcase("Chapter "//h%num//".  "//h%text), .true.)
        else
            call ts_mark(doc%engine, upcase(h%text), .true.)
        end if
        call ts_vkeep(doc%engine, ts_glue_t(50.0_dp*b/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        sub = ctx
        sub%bold = .true.
        if (len(h%num) > 0) then
            sub%size = 2.074_dp*b
            call ts_begin_par(doc%engine, ALIGN_LEFT, 0.0_dp, size=sub%size, &
                              leading=25.0_dp*b/10.0_dp, skip=.false., nobreak=.true.)
            call md_inline(doc, "Chapter "//h%num, sub)
            call ts_end_par(doc%engine)
            call ts_penalty(doc%engine, 10000)
            call ts_vskip(doc%engine, ts_glue_t(20.0_dp*b/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        end if
        sub%size = 2.488_dp*b
        call ts_begin_par(doc%engine, ALIGN_LEFT, 0.0_dp, size=sub%size, &
                          leading=30.0_dp*b/10.0_dp, skip=.false., nobreak=.true.)
        call md_inline(doc, h%text, sub)
        call ts_end_par(doc%engine)
        call ts_penalty(doc%engine, 10000)
        call ts_vskip(doc%engine, ts_glue_t(40.0_dp*b/10.0_dp, 0.0_dp, 0.0_dp, 0, 0))
        call ts_nobreak_next(doc%engine)
        call md_noindent(doc, .true.)
    end subroutine book_heading

    function upcase(s) result(t)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: t
        integer :: k, c
        t = s
        do k = 1, len(s)
            c = iachar(s(k:k))
            if (c >= iachar("a") .and. c <= iachar("z")) t(k:k) = achar(c - 32)
        end do
    end function upcase

end program plot_book_chapter
