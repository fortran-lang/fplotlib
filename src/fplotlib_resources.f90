! One-time preparation of the built-in, shared read-only resource tables.
module fplotlib_resources
    use fplotlib_status
    use fplotlib_glyphs, only: initialize_glyphs
    use fplotlib_hyph, only: initialize_hyphenation
    implicit none
    private
    public :: initialize_resources

contains

    ! Call serially before starting concurrent explicit-context work. Ordinary
    ! serial entrypoints also call this; after preparation it only reads flags.
    subroutine initialize_resources(status)
        type(status_t), intent(out) :: status
        call initialize_glyphs(status)
        if (.not. status%ok()) return
        call initialize_hyphenation()
    end subroutine initialize_resources

end module fplotlib_resources
