! An article with equations
! =========================
!
! A short scientific article: a title block and an abstract from the
! front matter, numbered sections, displayed equations numbered and
! referred to by name, a case distinction, a matrix, an aligned
! derivation, a list and a quotation. It runs over two pages, cut where
! TeX's page builder would cut them.
!
! The text is a strict MyST subset and the mathematics is TeX's.
! ``$$ ... $$ (eq:name)`` labels and numbers a display, and the ``{eq}`` role
! refers to it. Paragraphs are broken into lines as TeX breaks them, with the same
! hyphenation, and the spacing around headings, lists and displays is
! LaTeX's article class.
!
! The backslash in these strings is a real character. That is the default
! for gfortran, flang and ifx. A compiler that treats ``\`` as an escape
! wants ``\\`` in the literal.
!
! In a real project, keep the Markdown in a separate ``.md`` file and pass it
! to ``typeset_file("article.md", "article.svg")``. Here the document is
! assembled inline with ``//`` and ``achar(10)`` so the example is
! self-contained and avoids fixed-length character array truncation.

program plot_article
    use fplotlib, only: typeset
    implicit none
    character, parameter :: NL = achar(10)

    call typeset( &
        "---"//NL// &
        "title: The Damped Harmonic Oscillator"//NL// &
        "author: A. N. Author"//NL// &
        "date: November 2026"//NL// &
        "abstract: We derive the motion of a mass on a spring slowed by friction,"//NL// &
        "  classify its three regimes and compute the rate at which it loses energy."//NL// &
        "  The article is written in Markdown with TeX mathematics, and typeset by"//NL// &
        "  fplotlib."//NL// &
        "numbersections: true"//NL// &
        "---"//NL//NL// &
        "# Introduction"//NL//NL// &
        "A mass $m$ on a spring of stiffness $k$, slowed by a friction force"//NL// &
        "proportional to its velocity, obeys Newton’s second law,"//NL// &
        "$$ m\ddot{x} + c\dot{x} + kx = 0, $$ (eq:motion)"//NL// &
        "where $c$ is the damping coefficient. Dividing by $m$ and writing"//NL// &
        "$\omega_0 = \sqrt{k/m}$ for the natural frequency and"//NL// &
        "$\zeta = c/(2\sqrt{mk})$ for the damping ratio gives the standard form"//NL// &
        "$$ \ddot{x} + 2\zeta\omega_0\dot{x} + \omega_0^2 x = 0. $$ (eq:standard)"//NL// &
        "These two numbers are all that is left of the three constants we started"//NL// &
        "with: the frequency sets the time scale of the motion, and the damping ratio"//NL// &
        "its shape. Every mechanical, electrical or acoustic system that is linear"//NL// &
        "and of second order behaves in the same way, which is why the oscillator is"//NL// &
        "the first model studied in so many branches of physics and engineering."//NL//NL// &
        "# Solution"//NL//NL// &
        "Trying $x = e^{\lambda t}$ in {eq}`eq:standard` turns the differential"//NL// &
        "equation into an algebraic one, whose roots are"//NL// &
        "$$ \lambda_{1,2} = -\zeta\omega_0 \pm \omega_0\sqrt{\zeta^2 - 1}. $$ (eq:roots)"//NL// &
        "The sign of the discriminant decides the behaviour, and with"//NL// &
        "$\omega_d = \omega_0\sqrt{1 - \zeta^2}$ the general solution is"//NL// &
        "$$ x(t) = \begin{cases} e^{-\zeta\omega_0 t}"// &
        "\left(A\cos\omega_d t + B\sin\omega_d t\right)"//NL// &
        "   & \zeta < 1, \\ (A + Bt)\,e^{-\omega_0 t} & \zeta = 1, \\"//NL// &
        "   A e^{\lambda_1 t} + B e^{\lambda_2 t} & \zeta > 1, \end{cases} $$"// &
        " (eq:regimes)"//NL// &
        "the constants $A$ and $B$ being fixed by the initial position and velocity."//NL// &
        "The three cases of {eq}`eq:regimes` are the three regimes of the oscillator:"//NL//NL// &
        "- *underdamped*, $\zeta < 1$: the mass oscillates, its amplitude decaying as"//NL// &
        "  $e^{-\zeta\omega_0 t}$;"//NL// &
        "- *critically damped*, $\zeta = 1$: it returns to rest in the shortest time"//NL// &
        "  without overshooting;"//NL// &
        "- *overdamped*, $\zeta > 1$: it creeps back, the more slowly the larger"//NL// &
        "  $\zeta$ is."//NL//NL// &
        "## As a first-order system"//NL//NL// &
        "Writing $v = \dot{x}$ for the velocity turns {eq}`eq:motion` into a linear"//NL// &
        "system of two equations of the first order,"//NL// &
        "$$ \frac{d}{dt}\begin{pmatrix} x \\ v \end{pmatrix} = "// &
        "\begin{pmatrix} 0 & 1 \\"//NL// &
        "   -\omega_0^2 & -2\zeta\omega_0 \end{pmatrix} "// &
        "\begin{pmatrix} x \\ v \end{pmatrix}, $$"//NL// &
        "whose matrix has the trace $-2\zeta\omega_0$ and the determinant"//NL// &
        "$\omega_0^2$. Its eigenvalues are the roots {eq}`eq:roots`, and its"//NL// &
        "eigenvectors the directions in the phase plane along which the motion is a"//NL// &
        "pure exponential."//NL//NL// &
        "# Energy"//NL//NL// &
        "The energy of the oscillator is $E = \tfrac{1}{2}mv^2 + \tfrac{1}{2}kx^2$,"//NL// &
        "kinetic and potential. By {eq}`eq:motion` it changes at the rate"//NL// &
        "$$ \begin{aligned} \frac{dE}{dt} &= m v \dot{v} + k x v \\"// &
        " &= v\,(m\ddot{x} + kx) \\"//NL// &
        "   &= -c v^2 \le 0, \end{aligned} $$ (eq:energy)"//NL// &
        "so friction dissipates energy at the rate $cv^2$, and the oscillation dies"//NL// &
        "away. Without friction, $c = 0$, the energy is conserved and the mass"//NL// &
        "oscillates for ever with the frequency $\omega_0$."//NL//NL// &
        "> All models are wrong, but some are useful."//NL//NL// &
        "Real springs are not exactly linear, and real friction is not exactly"//NL// &
        "proportional to the velocity; yet the two parameters of {eq}`eq:standard`"//NL// &
        "describe a remarkable range of systems, from a car’s suspension to the tuned"//NL// &
        "circuit of a radio receiver."//NL//NL// &
        "# Conclusion"//NL//NL// &
        "The damped oscillator reduces to a single equation with two parameters. Its"//NL// &
        "characteristic roots {eq}`eq:roots` classify its motion, its matrix form"//NL// &
        "connects it with linear algebra, and its energy balance {eq}`eq:energy`"//NL// &
        "shows where the energy goes. The same analysis applies, almost word for"//NL// &
        "word, to any linear system of the second order."//NL, &
        "article.svg")
end program plot_article
