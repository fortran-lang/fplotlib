! An article with equations
! =========================
!
! A short scientific article: a title block and an abstract from the
! front matter, numbered sections, displayed equations numbered and
! referred to by name, a case distinction, a matrix, an aligned
! derivation, a list and a quotation. It runs over two pages, cut where
! TeX's page builder would cut them.
!
! The text is Markdown, as Pandoc reads it; the mathematics is TeX's.
! ``$$ ... $$ {#eq:name}`` numbers a display, and ``@eq:name`` refers to
! it. Paragraphs are broken into lines as TeX breaks them, with the same
! hyphenation, and the spacing around headings, lists and displays is
! LaTeX's article class.
!
! The backslash in these strings is a real character. That is the default
! for gfortran, flang and ifx. A compiler that treats ``\`` as an escape
! wants ``\\`` in the literal.

program plot_article
    use fplotlib, only: typeset
    implicit none

    call typeset([character(len=100) :: &
        "---", &
        "title: The Damped Harmonic Oscillator", &
        "author: A. N. Author", &
        "date: November 2026", &
        "abstract: We derive the motion of a mass on a spring slowed by friction, classify its", &
        "  three regimes and compute the rate at which it loses energy. The article is written", &
        "  in Markdown with TeX mathematics, and typeset by fplotlib.", &
        "numbersections: true", &
        "---", &
        "", &
        "# Introduction", &
        "", &
        "A mass $m$ on a spring of stiffness $k$, slowed by a friction force proportional to", &
        "its velocity, obeys Newton’s second law,", &
        "$$ m\ddot{x} + c\dot{x} + kx = 0, $$ {#eq:motion}", &
        "where $c$ is the damping coefficient. Dividing by $m$ and writing", &
        "$\omega_0 = \sqrt{k/m}$ for the natural frequency and $\zeta = c/(2\sqrt{mk})$ for the", &
        "damping ratio gives the standard form", &
        "$$ \ddot{x} + 2\zeta\omega_0\dot{x} + \omega_0^2 x = 0. $$ {#eq:standard}", &
        "These two numbers are all that is left of the three constants we started with: the", &
        "frequency sets the time scale of the motion, and the damping ratio its shape. Every", &
        "mechanical, electrical or acoustic system that is linear and of second order behaves", &
        "in the same way, which is why the oscillator is the first model studied in so many", &
        "branches of physics and engineering.", &
        "", &
        "# Solution", &
        "", &
        "Trying $x = e^{\lambda t}$ in @eq:standard turns the differential equation into an", &
        "algebraic one, whose roots are", &
        "$$ \lambda_{1,2} = -\zeta\omega_0 \pm \omega_0\sqrt{\zeta^2 - 1}. $$ {#eq:roots}", &
        "The sign of the discriminant decides the behaviour, and with", &
        "$\omega_d = \omega_0\sqrt{1 - \zeta^2}$ the general solution is", &
        "$$ x(t) = \begin{cases} e^{-\zeta\omega_0 t}\left(A\cos\omega_d t + B\sin\omega_d t\right)", &
        "   & \zeta < 1, \\ (A + Bt)\,e^{-\omega_0 t} & \zeta = 1, \\", &
        "   A e^{\lambda_1 t} + B e^{\lambda_2 t} & \zeta > 1, \end{cases} $$ {#eq:regimes}", &
        "the constants $A$ and $B$ being fixed by the initial position and velocity. The three", &
        "cases of @eq:regimes are the three regimes of the oscillator:", &
        "", &
        "- *underdamped*, $\zeta < 1$: the mass oscillates, its amplitude decaying as", &
        "  $e^{-\zeta\omega_0 t}$;", &
        "- *critically damped*, $\zeta = 1$: it returns to rest in the shortest time without", &
        "  overshooting;", &
        "- *overdamped*, $\zeta > 1$: it creeps back, the more slowly the larger $\zeta$ is.", &
        "", &
        "## As a first-order system", &
        "", &
        "Writing $v = \dot{x}$ for the velocity turns @eq:motion into a linear system of two", &
        "equations of the first order,", &
        "$$ \frac{d}{dt}\begin{pmatrix} x \\ v \end{pmatrix} = \begin{pmatrix} 0 & 1 \\", &
        "   -\omega_0^2 & -2\zeta\omega_0 \end{pmatrix} \begin{pmatrix} x \\ v \end{pmatrix}, $$", &
        "whose matrix has the trace $-2\zeta\omega_0$ and the determinant $\omega_0^2$. Its", &
        "eigenvalues are the roots @eq:roots, and its eigenvectors the directions in the phase", &
        "plane along which the motion is a pure exponential.", &
        "", &
        "# Energy", &
        "", &
        "The energy of the oscillator is $E = \tfrac{1}{2}mv^2 + \tfrac{1}{2}kx^2$, kinetic and", &
        "potential. By @eq:motion it changes at the rate", &
        "$$ \begin{aligned} \frac{dE}{dt} &= m v \dot{v} + k x v \\ &= v\,(m\ddot{x} + kx) \\", &
        "   &= -c v^2 \le 0, \end{aligned} $$ {#eq:energy}", &
        "so friction dissipates energy at the rate $cv^2$, and the oscillation dies away. Without", &
        "friction, $c = 0$, the energy is conserved and the mass oscillates for ever with the", &
        "frequency $\omega_0$.", &
        "", &
        "> All models are wrong, but some are useful.", &
        "", &
        "Real springs are not exactly linear, and real friction is not exactly proportional to", &
        "the velocity; yet the two parameters of @eq:standard describe a remarkable range of", &
        "systems, from a car’s suspension to the tuned circuit of a radio receiver.", &
        "", &
        "# Conclusion", &
        "", &
        "The damped oscillator reduces to a single equation with two parameters. Its", &
        "characteristic roots @eq:roots classify its motion, its matrix form connects it with", &
        "linear algebra, and its energy balance @eq:energy shows where the energy goes. The", &
        "same analysis applies, almost word for word, to any linear system of the second order."], &
        "article.svg")
end program plot_article
