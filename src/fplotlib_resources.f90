! One-time preparation of the built-in, shared read-only resource tables.
module fplotlib_resources
    use fplotlib_status
    use fplotlib_glyphs, only: initialize_glyphs
    implicit none
    private
    public :: initialize_resources

contains

    ! Call serially before starting concurrent explicit-context work. Ordinary
    ! serial entrypoints also call this; after preparation it only reads flags.
    subroutine initialize_resources(status)
        type(status_t), intent(out) :: status
        call initialize_glyphs(status)
    end subroutine initialize_resources

end module fplotlib_resources
