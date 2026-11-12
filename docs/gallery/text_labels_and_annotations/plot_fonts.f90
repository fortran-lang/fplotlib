! Fonts and characters
! ====================
!
! The two fonts fplotlib draws with, and a sample of what they cover.
! Text is Lato, in three faces: regular, bold and italic, chosen with
! ``fontweight=`` and ``fontstyle=`` (a label asking for both is set in
! bold). Math is Lete Sans Math, a sans-serif math font drawn to match
! Lato. Both are compiled into the library, so every format draws the
! same glyphs: PNG fills the outlines, SVG defines each glyph once and
! reuses it, and PDF and EPS embed them as fonts that keep the text
! selectable. Nothing depends on the fonts installed on the machine that
! draws or views the figure.
!
! Strings are UTF-8, typed directly in the Fortran source. Text covers
! every European language written in Latin script, and modern Greek; a
! letter typed as a base letter followed by a combining accent is set as
! the accented letter. Text is kerned with Lato's own pairs.

program plot_fonts
    use fplotlib, only: axis, dp, figtext, figure, savefig
    implicit none

    real(dp) :: y
    ! The figure's height, and the height of a row and of a heading, in
    ! inches; the rows are placed in figure coordinates.
    real(dp), parameter :: H = 11.4_dp, ROW_H = 0.32_dp, HEAD_H = 0.5_dp
    ! Where the captions and the samples start, across the figure.
    real(dp), parameter :: X0 = 0.03_dp, X1 = 0.25_dp

    call figure(figsize=[12.0_dp, H])
    call axis("off")
    y = 1.0_dp - 0.15_dp/H

! %%
! The three faces of Lato, and a range of sizes. A rotated label is the
! same glyphs, turned.

    call heading(y, "Text: Lato")
    call row(y, "regular", "The quick brown fox jumps over the lazy dog 0123456789")
    call row(y, "bold", "The quick brown fox jumps over the lazy dog 0123456789", &
             weight="bold")
    call row(y, "italic", "The quick brown fox jumps over the lazy dog 0123456789", &
             style="italic")
    y = y - 0.3_dp*ROW_H/H
    call figtext(X1, y, "8 pt", fontsize=8.0_dp, va="center")
    call figtext(X1 + 0.06_dp, y, "11 pt", fontsize=11.0_dp, va="center")
    call figtext(X1 + 0.14_dp, y, "15 pt", fontsize=15.0_dp, va="center")
    call figtext(X1 + 0.25_dp, y, "20 pt", fontsize=20.0_dp, va="center")
    call figtext(X1 + 0.39_dp, y, "28 pt", fontsize=28.0_dp, va="center")
    call figtext(X1 + 0.60_dp, y, "rotated", fontsize=13.0_dp, va="center", ha="center", &
                 rotation=30.0_dp)
    call figtext(X0, y, "sizes", fontsize=12.0_dp, va="center", color="dimgray")
    y = y - 1.5_dp*ROW_H/H

! %%
! A sample of the languages. Each line uses the letters its language
! adds to the Latin alphabet: carons and rings, ogoneks, cedillas,
! umlauts and the sharp s, double acute accents, the commas below of
! Romanian, the dotless i of Turkish, the thorn and eth of Icelandic.

    call heading(y, "Languages")
    call row(y, "Czech", "Příliš žluťoučký kůň úpěl ďábelské ódy")
    call row(y, "Polish", "Zażółć gęślą jaźń. Pchnąć w tę łódź jeża")
    call row(y, "French", "Le cœur déçu mais l’âme plutôt naïve, Louÿs rêva de crapaüter")
    call row(y, "German", "Zwölf Boxkämpfer jagen Viktor quer über den großen Sylter Deich")
    call row(y, "Spanish, Portuguese", "¿Qué pingüino? ¡El ñandú! — Ação, São Paulo, à beça")
    call row(y, "Nordic, Icelandic", "Blåbærsyltetøy på Ærø · Þórður og Ðóra · Åsa, Öland")
    call row(y, "Hungarian", "Árvíztűrő tükörfúrógép")
    call row(y, "Romanian, Turkish", "Șoseaua țării · Iğdır’da ışık, şeker ve çiçek")
    call row(y, "Baltic, Croatian", "Ąžuolas, ėglė · Ģērbies, ķēniņ! · Đak, ćevapčići")
    call row(y, "Welsh, Maltese, Esperanto", "Ŵyn ŷd · Ħal Għargħur · Eĥoŝanĝo ĉiuĵaŭde")
    call row(y, "Greek", "Ξεσκεπάζω την ψυχοφθόρα βδελυγμία · ΑΒΓΔ αβγδ ϊΐ")

! %%
! Typography beyond the letters: the quotes of several languages, dashes,
! currency and the common signs, and the super- and subscript digits,
! which need no math.

    call heading(y, "Punctuation and signs")
    call row(y, "quotes, dashes", "„Anführung“ “quoted” ‘single’ «guillemets» ‹›  - – —  …")
    call row(y, "signs", "€ £ ¥ ¢  © ® ™  ‰ % °  ± × ÷ ½ ¼  § ¶ † ‡ • № ℓ Ω")
    call row(y, "super, subscripts", "x² + y³ = z⁴ · H₂O · CO₂ · 10⁻⁶ m · 25 °C")

! %%
! Math is set in Lete Sans Math. Letters are italic and digits upright, as
! in TeX, and the alphabet commands choose the others; bold covers Greek
! and digits too. Greek capitals stand upright, and the variant forms of
! the lowercase letters are glyphs of their own. The formulas themselves,
! and every command, are in ``plot_mathtext_examples.f90``.

    call heading(y, "Math: Lete Sans Math")
    call row(y, "alphabets", "$abc\,ABC\,123$  $\mathrm{abc\,ABC}$  $\mathbf{abc\,ABC\,123}$  $\mathsf{abc\,ABC}$  $\mathbb{NZQRC}$  $\mathcal{ABFHLO}$")
    call row(y, "Greek", "$\alpha\beta\gamma\delta\zeta\eta\lambda\mu\xi\pi\sigma\chi\psi\omega\ \Gamma\Delta\Theta\Lambda\Xi\Pi\Sigma\Phi\Psi\Omega$")
    call row(y, "bold Greek", "$\mathbf{\alpha\beta\gamma\delta\omega\ \Gamma\Delta\Omega}$")
    call row(y, "variants", "$\epsilon\,\varepsilon\quad \theta\,\vartheta\quad \phi\,\varphi\quad \rho\,\varrho\quad \pi\,\varpi\quad \sigma\,\varsigma$")

! %%
! Text and math together. A label can mix both freely, in any language.
! Math keeps the regular weight inside a bold label: a bold math font is
! not included yet.

    call heading(y, "Text and math together")
    call row(y, "mixed", "Die Lösung ist $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$, n’est-ce pas?", &
             rows=1.6_dp)
    call row(y, "bold label", "Résumé: $E = mc^2$", weight="bold")

    call savefig("fonts.svg")
    print *, "wrote fonts.svg"

contains

    subroutine heading(y, title)
        real(dp), intent(inout) :: y
        character(len=*), intent(in) :: title

        y = y - 0.15_dp/H
        call figtext(X0, y, title, fontsize=15.0_dp, fontweight="bold", va="center")
        y = y - (HEAD_H - 0.15_dp)/H
    end subroutine heading

    ! One row: a caption, and the sample at its right. A tall sample takes
    ! more than one row's height.
    subroutine row(y, caption, sample, weight, style, rows)
        real(dp), intent(inout) :: y
        character(len=*), intent(in) :: caption, sample
        character(len=*), intent(in), optional :: weight, style
        real(dp), intent(in), optional :: rows
        real(dp) :: n

        n = 1.0_dp
        if (present(rows)) n = rows
        y = y - 0.5_dp*(n - 1.0_dp)*ROW_H/H
        call figtext(X0, y, caption, fontsize=12.0_dp, va="center", color="dimgray")
        if (present(weight) .and. present(style)) then
            call figtext(X1, y, sample, fontsize=15.0_dp, va="center", &
                         fontweight=weight, fontstyle=style)
        else if (present(weight)) then
            call figtext(X1, y, sample, fontsize=15.0_dp, va="center", fontweight=weight)
        else if (present(style)) then
            call figtext(X1, y, sample, fontsize=15.0_dp, va="center", fontstyle=style)
        else
            call figtext(X1, y, sample, fontsize=15.0_dp, va="center")
        end if
        y = y - (0.5_dp*(n - 1.0_dp) + 1.0_dp)*ROW_H/H
    end subroutine row

end program plot_fonts
