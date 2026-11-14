! Internal native-template policy, not a public template language or graphics IR.
module fplotlib_doctemplate
    use fplotlib_status
    use fplotlib_style, only: dp
    use fplotlib_typeset, only: ts_glue_t, ALIGN_JUSTIFY, ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT
    implicit none
    private
    public :: document_style_t, part_style_t, template_part_t, template_step_t, template_t
    public :: native_template, template_part_index
    public :: STEP_BODY, STEP_PART, STEP_TITLE_BLOCK, STEP_TITLE, STEP_FILL

    integer, parameter :: STEP_BODY = 1, STEP_PART = 2, STEP_TITLE_BLOCK = 3, STEP_TITLE = 4, STEP_FILL = 5

    type :: document_style_t
        real(dp) :: BASE = 10.0_dp, LEAD = 1.2_dp, PARINDENT = -1.0_dp
        type(ts_glue_t) :: PARSKIP_G = ts_glue_t(0.0_dp, 1.0_dp, 0.0_dp, 0, 0)
        integer :: DOC_ALIGN = ALIGN_JUSTIFY
        integer :: TEXT_COL(3) = 0, PAGE_COL(3) = 255
        real(dp) :: page_width = 595.2756_dp, page_height = 841.8898_dp
        real(dp) :: margins(4) = 72.0_dp
        logical :: page_numbers = .true., BOOK = .false.
    end type document_style_t

    type :: part_style_t
        real(dp) :: font_scale = 1.0_dp
        integer :: align = -1, indent = -1
        logical :: bold = .false., italic = .false., has_color = .false.
        integer :: color(3) = 0
        real(dp) :: before_base = 0.0_dp, after_base = 0.0_dp
        real(dp) :: before_fixed = 0.0_dp, after_fixed = 0.0_dp
    end type part_style_t

    type :: template_part_t
        character(len=16) :: name = ""
        type(part_style_t) :: style
    end type template_part_t

    type :: template_step_t
        integer :: kind = STEP_BODY
        integer :: part = 0
    end type template_step_t

    type :: template_t
        character(len=16) :: name = "article"
        type(document_style_t) :: body
        type(part_style_t) :: title
        type(template_part_t), allocatable :: parts(:)
        type(template_step_t), allocatable :: steps(:)
    end type template_t

contains

    subroutine native_template(name, template, status)
        character(len=*), intent(in) :: name
        type(template_t), intent(out) :: template
        type(status_t), intent(out) :: status
        select case (name)
        case ("article", "book")
            template%name = name
            if (name == "book") then
                template%body%BOOK = .true.
                template%body%page_width = 419.5276_dp
                template%body%page_height = 595.2756_dp
                template%body%margins = 72.0_dp*1.8_dp/2.54_dp
                template%body%margins(3) = 72.0_dp*2.2_dp/2.54_dp
            end if
            allocate (template%parts(1), template%steps(2))
            template%parts(1)%name = "abstract"
            template%steps = [template_step_t(STEP_TITLE_BLOCK, 1), template_step_t(STEP_BODY)]
        case ("letter")
            template%name = name
            template%body%page_width = 612.0_dp
            template%body%page_height = 792.0_dp
            template%body%margins = 79.2_dp
            template%body%BASE = 11.0_dp
            template%body%PARINDENT = 0.0_dp
            template%body%PARSKIP_G = ts_glue_t(6.0_dp, 1.2_dp, 0.0_dp, 0, 0)
            template%body%page_numbers = .false.
            allocate (template%parts(5), template%steps(6))
            template%parts(1) = template_part_t("sender", part_style_t(align=ALIGN_RIGHT, indent=0, &
                                                    before_base=1.0_dp, after_base=1.0_dp))
            template%parts(2) = template_part_t("recipient", part_style_t(align=ALIGN_LEFT, indent=0))
            template%parts(3) = template_part_t("opening", part_style_t(align=ALIGN_LEFT, indent=0, before_base=1.2_dp))
            template%parts(4) = template_part_t("closing", part_style_t(align=ALIGN_LEFT, indent=0, before_base=1.2_dp))
            template%parts(5) = template_part_t("signature", part_style_t(align=ALIGN_LEFT, indent=0, &
                                                    before_fixed=72.0_dp*1.2_dp/2.54_dp))
            template%steps = [template_step_t(STEP_PART, 1), template_step_t(STEP_PART, 2), &
                              template_step_t(STEP_PART, 3), template_step_t(STEP_BODY), &
                              template_step_t(STEP_PART, 4), template_step_t(STEP_PART, 5)]
        case ("invitation")
            template%name = name
            template%body%page_width = 360.0_dp
            template%body%page_height = 504.0_dp
            template%body%margins = 39.6_dp
            template%body%BASE = 12.0_dp
            template%body%PARINDENT = 0.0_dp
            template%body%PARSKIP_G = ts_glue_t(8.0_dp, 1.6_dp, 0.0_dp, 0, 0)
            template%body%DOC_ALIGN = ALIGN_CENTER
            template%body%TEXT_COL = [59, 43, 35]
            template%body%PAGE_COL = [251, 243, 228]
            template%body%page_numbers = .false.
            template%title = part_style_t(font_scale=2.488_dp, align=ALIGN_CENTER, bold=.true., &
                                          has_color=.true., color=[139, 26, 26])
            allocate (template%parts(3), template%steps(7))
            template%parts(1) = template_part_t("intro", part_style_t(font_scale=1.2_dp, indent=0, italic=.true., &
                                                    has_color=.true., color=[154, 106, 58]))
            template%parts(2) = template_part_t("ornament", part_style_t(indent=0, &
                                                    has_color=.true., color=[192, 138, 62]))
            template%parts(3) = template_part_t("reply", part_style_t(font_scale=0.9_dp, indent=0, &
                                                    has_color=.true., color=[154, 106, 58]))
            template%steps = [template_step_t(STEP_FILL), template_step_t(STEP_PART, 1), &
                              template_step_t(STEP_TITLE), template_step_t(STEP_PART, 2), &
                              template_step_t(STEP_BODY), template_step_t(STEP_PART, 3), template_step_t(STEP_FILL)]
        case default
            call status%set(ERROR_UNSUPPORTED, "MyST: native template must be article, book, letter or invitation")
        end select
    end subroutine native_template

    pure integer function template_part_index(template, name) result(part)
        type(template_t), intent(in) :: template
        character(len=*), intent(in) :: name
        integer :: i
        part = 0
        if (.not. allocated(template%parts)) return
        do i = 1, size(template%parts)
            if (template%parts(i)%name /= name) cycle
            part = i
            return
        end do
    end function template_part_index

end module fplotlib_doctemplate
