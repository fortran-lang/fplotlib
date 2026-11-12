! fplotlib_glyphs_data -- glyph outlines, metrics and kerning, generated
! by tools/gen_glyphs.py. Do not edit.
!
! The glyph data in this file is derived from two fonts:
!
!   * Lato 2.015, copyright (c) 2010-2014 by tyPoland Lukasz Dziedzic
!     (team@latofonts.com) with Reserved Font Name "Lato"; licence
!     in LICENSE_LATO;
!   * Lete Sans Math 0.63, copyright (c) Chenjing Bu and Daniel Flipo,
!     built on Fira Math (copyright (c) Xiangdong Zeng) and Lato, and
!     inheriting Lato's Reserved Font Name; licence in LICENSE_LETE.
!
! Both are licensed under the SIL Open Font License, Version 1.1. The
! rest of fplotlib is MIT; this file is OFL-1.1.
!
! One base85 string holds every face: glyph outlines, advance widths
! and ink boxes in integer font units, each face's cmap and its pair
! kerning, and the math face's MATH table. Lato's outlines are stored
! as cubics at 1000 units to the em, many of them as Lete Sans Math's.
! fplotlib_glyphs unpacks it on first
! use; the format is described there and in the generator.

module fplotlib_glyphs_data
    implicit none
    public

    integer, parameter :: NFACE = 4
    integer, parameter :: NGLYPH = 2773
    integer, parameter :: NCONT = 2802
    integer, parameter :: NPT = 51914
    integer, parameter :: NCOMP = 1392
    integer, parameter :: NCMAP = 2172
    integer, parameter :: NKERN = 52100

    ! Per face: how many glyphs it has, its units per em, ascender,
    ! descender, x-height and cap height in its own units, whether its
    ! outlines are cubic (CFF) or quadratic (TrueType), and the face its
    ! advance widths are predicted from, 0 for the glyph before.
    integer, parameter :: FACE_NG(4) = [ &
        545, 546, 541, 1141]
    integer, parameter :: FACE_EM(4) = [ &
        2000, 2000, 2000, 1000]
    integer, parameter :: FACE_ASC(4) = [ &
        1974, 1974, 1974, 750]
    integer, parameter :: FACE_DESC(4) = [ &
        -426, -426, -426, -250]
    integer, parameter :: FACE_XH(4) = [ &
        1013, 1026, 1013, 450]
    integer, parameter :: FACE_CAP(4) = [ &
        1433, 1446, 1433, 662]
    logical, parameter :: FACE_CUBIC(4) = [.true., .true., .true., .true.]

    ! The font units an outline unit is, and the face a composite's
    ! components may come from as well as its own, 0 for none.
    integer, parameter :: FACE_OSCALE(4) = [ &
        2, 2, 2, 1]
    integer, parameter :: FACE_XREF(4) = [ &
        4, 4, 4, 0]
    ! Whether a face's glyphs may be stored as differences from others.
    logical, parameter :: FACE_RESID(4) = [.false., .false., .false., .true.]
    integer, parameter :: FACE_PRED(4) = [ &
        0, 1, 1, 0]

    ! Kerning is in steps of KERN_STEP font units. A face uses the
    ! kerning of FACE_KERN, itself unless it shares another's, and
    ! stores its values as differences from those of FACE_KPRED, 0 for
    ! none.
    integer, parameter :: KERN_STEP = 5
    integer, parameter :: FACE_KERN(4) = [ &
        1, 1, 3, 4]
    integer, parameter :: FACE_KPRED(4) = [ &
        0, 0, 1, 0]
    logical, parameter :: FACE_HAS_MATH(4) = [.false., .false., .false., .true.]

    ! The math face's MATH table: how many size variants, assemblies,
    ! assembly parts, math kern heights and math kern values it has,
    ! the overlap two assembly parts must at least have, and the
    ! constants, in font units (two of them are percentages).
    integer, parameter :: NVAR = 275
    integer, parameter :: NASM = 30
    integer, parameter :: NPART = 81
    integer, parameter :: NMKH = 16
    integer, parameter :: NMKV = 1256
    integer, parameter :: MIN_CONNECTOR_OVERLAP = 20
    integer, parameter :: NMC = 56
    integer, parameter :: MC_SCRIPT_PERCENT_SCALE_DOWN = 1
    integer, parameter :: MC_SCRIPT_SCRIPT_PERCENT_SCALE_DOWN = 2
    integer, parameter :: MC_DELIMITED_SUB_FORMULA_MIN_HEIGHT = 3
    integer, parameter :: MC_DISPLAY_OPERATOR_MIN_HEIGHT = 4
    integer, parameter :: MC_MATH_LEADING = 5
    integer, parameter :: MC_AXIS_HEIGHT = 6
    integer, parameter :: MC_ACCENT_BASE_HEIGHT = 7
    integer, parameter :: MC_FLATTENED_ACCENT_BASE_HEIGHT = 8
    integer, parameter :: MC_SUBSCRIPT_SHIFT_DOWN = 9
    integer, parameter :: MC_SUBSCRIPT_TOP_MAX = 10
    integer, parameter :: MC_SUBSCRIPT_BASELINE_DROP_MIN = 11
    integer, parameter :: MC_SUPERSCRIPT_SHIFT_UP = 12
    integer, parameter :: MC_SUPERSCRIPT_SHIFT_UP_CRAMPED = 13
    integer, parameter :: MC_SUPERSCRIPT_BOTTOM_MIN = 14
    integer, parameter :: MC_SUPERSCRIPT_BASELINE_DROP_MAX = 15
    integer, parameter :: MC_SUB_SUPERSCRIPT_GAP_MIN = 16
    integer, parameter :: MC_SUPERSCRIPT_BOTTOM_MAX_WITH_SUBSCRIPT = 17
    integer, parameter :: MC_SPACE_AFTER_SCRIPT = 18
    integer, parameter :: MC_UPPER_LIMIT_GAP_MIN = 19
    integer, parameter :: MC_UPPER_LIMIT_BASELINE_RISE_MIN = 20
    integer, parameter :: MC_LOWER_LIMIT_GAP_MIN = 21
    integer, parameter :: MC_LOWER_LIMIT_BASELINE_DROP_MIN = 22
    integer, parameter :: MC_STACK_TOP_SHIFT_UP = 23
    integer, parameter :: MC_STACK_TOP_DISPLAY_STYLE_SHIFT_UP = 24
    integer, parameter :: MC_STACK_BOTTOM_SHIFT_DOWN = 25
    integer, parameter :: MC_STACK_BOTTOM_DISPLAY_STYLE_SHIFT_DOWN = 26
    integer, parameter :: MC_STACK_GAP_MIN = 27
    integer, parameter :: MC_STACK_DISPLAY_STYLE_GAP_MIN = 28
    integer, parameter :: MC_STRETCH_STACK_TOP_SHIFT_UP = 29
    integer, parameter :: MC_STRETCH_STACK_BOTTOM_SHIFT_DOWN = 30
    integer, parameter :: MC_STRETCH_STACK_GAP_ABOVE_MIN = 31
    integer, parameter :: MC_STRETCH_STACK_GAP_BELOW_MIN = 32
    integer, parameter :: MC_FRACTION_NUMERATOR_SHIFT_UP = 33
    integer, parameter :: MC_FRACTION_NUMERATOR_DISPLAY_STYLE_SHIFT_UP = 34
    integer, parameter :: MC_FRACTION_DENOMINATOR_SHIFT_DOWN = 35
    integer, parameter :: MC_FRACTION_DENOMINATOR_DISPLAY_STYLE_SHIFT_DOWN = 36
    integer, parameter :: MC_FRACTION_NUMERATOR_GAP_MIN = 37
    integer, parameter :: MC_FRACTION_NUM_DISPLAY_STYLE_GAP_MIN = 38
    integer, parameter :: MC_FRACTION_RULE_THICKNESS = 39
    integer, parameter :: MC_FRACTION_DENOMINATOR_GAP_MIN = 40
    integer, parameter :: MC_FRACTION_DENOM_DISPLAY_STYLE_GAP_MIN = 41
    integer, parameter :: MC_SKEWED_FRACTION_HORIZONTAL_GAP = 42
    integer, parameter :: MC_SKEWED_FRACTION_VERTICAL_GAP = 43
    integer, parameter :: MC_OVERBAR_VERTICAL_GAP = 44
    integer, parameter :: MC_OVERBAR_RULE_THICKNESS = 45
    integer, parameter :: MC_OVERBAR_EXTRA_ASCENDER = 46
    integer, parameter :: MC_UNDERBAR_VERTICAL_GAP = 47
    integer, parameter :: MC_UNDERBAR_RULE_THICKNESS = 48
    integer, parameter :: MC_UNDERBAR_EXTRA_DESCENDER = 49
    integer, parameter :: MC_RADICAL_VERTICAL_GAP = 50
    integer, parameter :: MC_RADICAL_DISPLAY_STYLE_VERTICAL_GAP = 51
    integer, parameter :: MC_RADICAL_RULE_THICKNESS = 52
    integer, parameter :: MC_RADICAL_EXTRA_ASCENDER = 53
    integer, parameter :: MC_RADICAL_KERN_BEFORE_DEGREE = 54
    integer, parameter :: MC_RADICAL_KERN_AFTER_DEGREE = 55
    integer, parameter :: MC_RADICAL_DEGREE_BOTTOM_RAISE_PERCENT = 56
    integer, parameter :: MATH_CONSTANT(56) = [ &
        70, 55, 1400, 1400, 150, 280, 527, 689, 220, 400, 200, 350, &
        250, 126, 416, 170, 400, 60, 150, 150, 150, 600, 450, 720, &
        480, 730, 200, 300, 300, 600, 150, 150, 450, 720, 480, 730, &
        66, 200, 66, 80, 135, 0, 0, 150, 66, 50, 150, 66, &
        50, 96, 142, 76, 76, 276, -400, 64]

    ! Code lengths of the prefix code for the magnitude classes of a
    ! delta, a Huffman code for this data.
    integer, parameter :: NCLASS = 15
    integer, parameter :: CLEN(15) = [ &
        2, 5, 4, 4, 4, 4, 3, 3, 3, 4, 6, 7, 8, 9, 9]

    ! Canonical composition of a base and one combining mark, for the
    ! characters of the text repertoire: text typed decomposed (NFD) is
    ! put back together through this before it is looked up.
    integer, parameter :: NRECOMP = 195
    integer, parameter :: RECOMP_BASE(195) = [ &
        65, 65, 65, 65, 65, 65, 67, 69, 69, 69, 69, 73, &
        73, 73, 73, 78, 79, 79, 79, 79, 79, 85, 85, 85, &
        85, 89, 97, 97, 97, 97, 97, 97, 99, 101, 101, 101, &
        101, 105, 105, 105, 105, 110, 111, 111, 111, 111, 111, 117, &
        117, 117, 117, 121, 121, 65, 97, 65, 97, 65, 97, 67, &
        99, 67, 99, 67, 99, 67, 99, 68, 100, 69, 101, 69, &
        101, 69, 101, 69, 101, 69, 101, 71, 103, 71, 103, 71, &
        103, 71, 103, 72, 104, 73, 105, 73, 105, 73, 105, 73, &
        105, 73, 74, 106, 75, 107, 76, 108, 76, 108, 76, 108, &
        78, 110, 78, 110, 78, 110, 79, 111, 79, 111, 79, 111, &
        82, 114, 82, 114, 82, 114, 83, 115, 83, 115, 83, 115, &
        83, 115, 84, 116, 84, 116, 85, 117, 85, 117, 85, 117, &
        85, 117, 85, 117, 85, 117, 87, 119, 89, 121, 89, 90, &
        122, 90, 122, 90, 122, 83, 115, 84, 116, 168, 913, 917, &
        919, 921, 927, 933, 937, 970, 921, 933, 945, 949, 951, 953, &
        971, 953, 965, 959, 965, 969, 87, 119, 87, 119, 87, 119, &
        89, 121, 61]
    integer, parameter :: RECOMP_MARK(195) = [ &
        768, 769, 770, 771, 776, 778, 807, 768, 769, 770, 776, 768, &
        769, 770, 776, 771, 768, 769, 770, 771, 776, 768, 769, 770, &
        776, 769, 768, 769, 770, 771, 776, 778, 807, 768, 769, 770, &
        776, 768, 769, 770, 776, 771, 768, 769, 770, 771, 776, 768, &
        769, 770, 776, 769, 776, 772, 772, 774, 774, 808, 808, 769, &
        769, 770, 770, 775, 775, 780, 780, 780, 780, 772, 772, 774, &
        774, 775, 775, 808, 808, 780, 780, 770, 770, 774, 774, 775, &
        775, 807, 807, 770, 770, 771, 771, 772, 772, 774, 774, 808, &
        808, 775, 770, 770, 807, 807, 769, 769, 807, 807, 780, 780, &
        769, 769, 807, 807, 780, 780, 772, 772, 774, 774, 779, 779, &
        769, 769, 807, 807, 780, 780, 769, 769, 770, 770, 807, 807, &
        780, 780, 807, 807, 780, 780, 771, 771, 772, 772, 774, 774, &
        778, 778, 779, 779, 808, 808, 770, 770, 770, 770, 776, 769, &
        769, 775, 775, 780, 780, 806, 806, 806, 806, 769, 769, 769, &
        769, 769, 769, 769, 769, 769, 776, 776, 769, 769, 769, 769, &
        769, 776, 776, 769, 769, 769, 768, 768, 769, 769, 776, 776, &
        768, 768, 824]
    integer, parameter :: RECOMP_CHAR(195) = [ &
        192, 193, 194, 195, 196, 197, 199, 200, 201, 202, 203, 204, &
        205, 206, 207, 209, 210, 211, 212, 213, 214, 217, 218, 219, &
        220, 221, 224, 225, 226, 227, 228, 229, 231, 232, 233, 234, &
        235, 236, 237, 238, 239, 241, 242, 243, 244, 245, 246, 249, &
        250, 251, 252, 253, 255, 256, 257, 258, 259, 260, 261, 262, &
        263, 264, 265, 266, 267, 268, 269, 270, 271, 274, 275, 276, &
        277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, &
        289, 290, 291, 292, 293, 296, 297, 298, 299, 300, 301, 302, &
        303, 304, 308, 309, 310, 311, 313, 314, 315, 316, 317, 318, &
        323, 324, 325, 326, 327, 328, 332, 333, 334, 335, 336, 337, &
        340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, &
        352, 353, 354, 355, 356, 357, 360, 361, 362, 363, 364, 365, &
        366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 376, 377, &
        378, 379, 380, 381, 382, 536, 537, 538, 539, 901, 902, 904, &
        905, 906, 908, 910, 911, 912, 938, 939, 940, 941, 942, 943, &
        944, 970, 971, 972, 973, 974, 7808, 7809, 7810, 7811, 7812, 7813, &
        7922, 7923, 8800]

    character(len=*), parameter :: ALPHABET = &
        "#$%()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz"

    integer, parameter :: BLOB_LEN = 167990
    character(len=118), parameter :: BLOB_ROWS_1(100) = [character(len=118) :: &
        "vzE8>#32+:UGsbk/1UyXvQavmWyh#`WZrq@_e3[)hBpa1*]vJA0;pZa5/q.CGk5]/`30mJ,<p*:#Bt_orr]Q[PJS=``LSdz-Qx+lx#(NlR*;u=[ur,SifV", &
        "O28@X[N)OxwtUW^YRt0D=;)_Q53gB^HuPie8GB^@h_A^WyO#]csHw/,FlR#>M47G+/-kRxRU#_eg]$_%0)[%cTPJ2+4.qS]F@__t//ocF8<Z_D%;-<XqBR", &
        "6EsoXs=L0OK@1WGRqfi.1.Q=i9`K3%*TwHgKRM@Y,Of1WYgouwTnjuW3asK[OfTeF%mzd?*owEbksIerC]t^Gu4E]*lBYj]Drze@gS8(5uQ2WSGYPtZU>0", &
        "UK6S*c[H;$_9k?FP4Xc*vf.0QjQgrt1$YN7sUW%-we?lYEOInp@NTI$=)fkK5:V>?gk;<:SeZCjfRFAg#kOOu8CVZ6/SQs$FK_rqI7cEj,5m`huNm-22$K", &
        "HMTgmSOk%#w3ewW/P.](32#ZQh?$k^4ea-UlSF)JW41p*WB5wZ0ip/*QZ-:)@O<H/*Tv9/]n#8YXIUGvadu-HO,Z6h>[:=f:=bOw5s>;F-UKZuj2)_afrc", &
        "t;tlJVDKEDr;MOyeBmF`[*<XRq_NBS@=Vs8Ob4ggeboe>abPp9h-O>AF29#aYxTK-T@6vjL:vlrrGEg9U`9;J>UKZk^y.[1B?M(X-i7b4.QOk3c$t8k@u(", &
        "<;_$*hzU-4m>C*-o/jGu+G^]tSJbwX*Rh,wj8k(4.rTkD%`ISFmuHx`?1p1g3,aDO]UEeH?iCWg6691qX=h(ChH8+`upl4,Tx]RVChgPSk5[1nH-UVFgt$", &
        "JAML@N5a39/#X/q%Ptf)oyJq%RhKM7RzMcj5o>-Ylx^lIl?d-#De5Ndve2crwuJ3L*#(E=W7zd3is2UeXFaCsfV#?i.WYU)j,K`?tiKo+vD0;2LM)+2>k+", &
        "3/2b=a?)(UqAgp*6s0Y@r9EdX7HA[92I1YEB4`3$_PS5CxW*I3X*4jkyv-At0[<>?tKvCz4rtc23:m%le*Zz7Qv>?AG?$TbhORtbP7e0DcPbVcksN?H^,C", &
        "b57ko50*/jy5vYjua`KM=0POP?@:krc=-`MZlg`j+nv)()$MqrIvy:C;Bf[]8Byw*f,oO2>SQ4RE]*$GaVA*IFszNi1H15Omi)RCZG(0[>:-D>%Ar>3@V/", &
        "HW`W+5f.x[WFjuQ[$riDc#)kt%x,tBId+?%f,rfEPhid)wOqmA6:7)<JmA?=n/1l8F87j/dDQlsRH>=6+n2App8D2rYSqGJ:k>mb/qf0#saGkJ?t*RBdCi", &
        "9#--R9<JXWi^7>[-s$=EXw7,CH6g>*.-F*l;EH^0M2oUKZ_-2C;NPPr+s34=#o_ocfhnTj0/Rg)I;eDt>w/ZD;yAZ.b;32mU=$n?BQ/QnZne,4E_)oysHO", &
        "W^;f,o*1B)?7hp:l+_FkEGE<N[8px25t.jb8?:p+2R`=OUN,Fg0ktO+`F8QRc[L%DKdUX.B4si1dZT%S-3P2P$61pYp]TzQTB$p)O`9f=1p3^V?^8vKn7.", &
        "m2M^EE#>;O6h5EL=9Z[RJlI3Qf8JXNQ1b%O%;Xaj8<Sw`7];U).v_cTLodo)QmIstmMvv=UZEDee)3Sd_w(fsT=N/o3%9viT(Xm:ScX5rwZnPwtgW.x/%2", &
        "%-%GL*Nu1N#kw$YgB=$.^Tt6rCrehAW,+][W3(HRXrO#mXYC.y=^uM^E6H8<tPPVq=aSl%#I)O*d/vPE@UMkJ<y^>tCg;0A*2UUoIH^N>pb[TBPIJt0R%n", &
        "J$($b.Q#:s+zj[yX;nJTZ(pH(l@fZFeRVu(:5/?V_cL73pe]Z(;PHM=?:Q=?un[Cxa[gWLW1PO@_e:H;=;KSaT<5:D[sq]V,tlo]4ud*c?]X^[P69P5:AR", &
        "H,$r#NU(sWl6V;cI@rk]i=hcpHuo9/Td1PkR4LKFd-ID(5j)RSOW>cNlG=OYvgC^qulf/(h6P6:FDR`^X[ZeF1K2Xmrc4M$@o;d+M7A[*iQ-(YL?C^?8EA", &
        "@2x_t8]@.@r,6%h@Pyjf5d,dNq-:CTTCM<OEVxa+rUeD9ZR9*.,fS6;VZ:K9V:tfR^wco=P=j3mgS(OC-/c`df6i.YHu@(anFrg_LZIrgnw%0sy>S=Q%z`", &
        "?W=>5@aFm#3YY3TXuiXuF2$/X2Q7PQL[-Q)o$Xj/BuHULpd6qd:V-kRUc(yCBXWP9X$/rhTZsSZPA@Did>Vn6YdA.T;,G2jC?mJQ+ZsW8_SfdURE]W8f.r", &
        "cw9%K_u_kuTSZ>[RL#1l$uldo_:b,A#D3*wz$I3AHfy8sSE_*KWI_mm.+L8nzfs]A5F^llaPWeVKj2B?,)x^eeeXI41,c_25%Yjl2;xiC$##A8$dA;N7F_", &
        "=5X.N25k%/.^EG++cjLm8lwH2f/(h4P-`LAPteQn5*@+hAKw,U?2E:3Ef-,h8jmeteQ0J.g=D^rNaj#IuZbF-M[3vCur5.$fb)Pe:;>BA6pa:n6`Uz`?/1", &
        "u)jsl$<]N>vZgoZLo=kxCy)y<1%6a5TzXYqZu%Jt@Bj/9?SNj:E]paY*BnIOdV[3NqdgeuYLqV;%ynJA8DBC_amY`Y91m$_-Wfrjo/Vk$45Ol%8+/q9sQs", &
        "RgvPV[ID%w<,:)pJ?lv-k;e)q*#SFma(6wq:Ftd%gesYWS?uGt?UA-XW=Ks<gn)t0IZDvI?zIOe%Ja5>D]6NvHC2RJH>%;fQia(8JCV`dA4dfIYaHvLisQ", &
        "_9W,QWXf^X_w0iz@l2g=tZV6W]S/iMFf.?bt<`j0/$zh3c)czgU^H0K//;7gb%d@YXCM(Q2#_o,$,cBk6eEcQ9GU3-#t]oI_J4TbvDKuZfOV6^jaE=>Lo6", &
        "UN)_gi#tO;x`zZ$vpAFR.bP9dNgW)U7,D3R7wqtPNLHoQEkp[f0,YO;l1bj<#L:kU/8Vi4WatXsPDM.>XNj;1b)e7;u`=*brnk$#yWxDMN9@%d@B2wfze=", &
        "0RH?UCr=.;q)me..7Tro)c<fqdxabVhsd/onP$-eO/5a4=7#]Bk]nMdfi<)4.)nQ-#hrjmYm-1*Uvky/Q#%?*Jw`p*nm%y+:00b*e5P.ew:?oFL-F-)DON", &
        "SrgcqIa]>p^<_z#AcCNhu_@Ag6AA1;@>uqPV>)aIirUuLC.PZ,5;%V8i69,n,HFSO7rP63y>:jty(rLPw+$O*8>XxETosmC21fi*]%p_Tf%c/ndErPeBE4", &
        "N8$Z,<B:W]FX]:i%oJs#PRxx5KsJAc,diik8I$[cDFDx=8GaWXz+@9kMN=YfmTX:OcgAR1UxoO^N7$fMji<0>7D2e5Tpx,75R?lpr)K.O_=WmD$Sy<4uy:", &
        "h,xsqm=pRE2`A],I.l$Y:FC76I>UY3L4oBNUPNRsuB?eMXrx`JHO49:-suY3Q$lb@lXo?GkO/T<yDl8ZqBHy<X3_j3:NZ893pF9Qkj_*oB<9B6Iuhzm)w%", &
        "ceNixlEBSvD*Xp3WVFcw2hZAQbv7UO*F2=2QsOD^Nx0#m^-L*0z<BJHi,G.?hA)q3sWy.Vt00>C4C-w<?+SM>=%dXvU`3BODjhig*<IY-<JTX511`AzskS", &
        "H6ioZCECfac)fmR4Ov^lne7o:RA,)):>)iy,xNZ%4%AsRE-Tz$K.@Zy<NV:)`ijb)S@wn[P5NMp:3wX.OJqSlk^SuYLz0m=]c-Ld+<9p/rDK#t<qH<B:r]", &
        "=]Y*:BHPX32a2BTg127Q#E1Z@o:vanx2<a%aoTCS:q(X3l2JumbNbEi=fw,=gGnQt]G^d/BL2#>;kO*0-IREF94`^*JULtB7(.c9WvCm_Sp;eetBHXA=?k", &
        "9V=6ug^]?p;,$SM$bOFv(*$/-:aav[*Fsqp5+8WR3wZA4/0Thrx^d)-%pGE)6r3NW/]-jg6xFE[%OwLrbKG.mtuV%A:i+Rq+RMb9Qt1S6`:cAl7J,jB=aG", &
        "vH[M.SefsPNr*kmIK0)ay^_ap[FpUEUfwdpbTCEUHT5YIgT?xA86twyqgyUwl#zdB1*)oJzf5XJRE6P0K98Kto8s7CBR_1`f?/cc39m)4fB7+nK#G>L]OJ", &
        "Gd1<5:y9OI`^O^t4@N^I08@PL*VPf1dT)hff/8()<>^qcQ-Bp(6pb+Ysta[1SdxuLi>M$,QgrR?FO@dsL<J8]C2TNbn=mXA+YuG%i[A$#>tl%nyL-Ip04u", &
        "9b*IfIziS4(iAK#*D$/l/GS5c5K/XAA,*gkR_jO@X==r#:P0n^7g+Wpf^tsX]@nHiN;RSCT-O(#XwPuq`Oz5ZdOy#SPcc.]WnzoV/NsZ[dH8.Gk]S8:%c$", &
        "nk]?)%2Hie[<1W/u.Pf9<AQkcmsQZqa5oJ$tXeAfpT4OLbYEfmSP`OjD5ha*f+ZBeJZ/OZTU$z+2]R0_ei]8]0/+nr3k8t(7ZO#77.^AY.)il#uM<zH8hP", &
        "uzl`V`/ax26wH0F%d?ZFJP7wDEpnMrJ674O9lE$qOgl$vpab,=J=@o,wtV:%<EG7BOBH[0:c$IB6D+:7XhS72Ft2O4TVW,7W74=%Y-[Cs+d*d*6>CutNa`", &
        "k;IKAv;CKXy*AZD@Dl#LwOd4sr^;m818Mwsu+8`w)tA)O?#GdwMB2voP-V#=ch7@r[,zst*^QHBK<b7Y4qwx]4Q3ff-5*8P8ADM3+j*^BtCrTApftQ9xWD", &
        "E#?%?dk8OHATOCdV@=3oBPsB$YR]3I$da=r^jS,pxZxmE>q?=2gqPEvoQvPMKDe*C[Gvd]TFU0kE4A:W+vf[u*-U,Ye$gDQlBq6?(@H-7*9W-3FZy@t`V#", &
        "0L1++4ZGkTl0wW++dqJr=p:[R;usjx<ImMK?wT)z_[lYiD>VgR<h7:q/1kGbt#+5O@D<lLst@n]<IXON.J?doTO*C68t%xR+1-MR4S`3+n7MB((s+L<,2v", &
        "RdIO%1)tF8bFBtl^O,[1_[U]vE3%hD3)YqO$46ae$j:14UhejT/;l,)e=OOHi]BN7dM>J;f^lRppJs8s.?AJ(qOr%$2FTAd9OAAAA[h:x9mEmgRy3jLM6p", &
        "]cb[oI,cH#Vy8iCb%(uXk)RHNk:rREsHWxJ]BdgVUGa)@bgXH7.Fi$SX>0S.b5ht%YakvWK(JxBXb*]bR3,<$qUB`,MLjP;d4D)[lGBc=?/iL3i>:y`@SB", &
        "2;=M0>g)exSZxA)F;QU9_%Xc>k4nwyanvasq7s7_Cn-,=6+;yzI0VJ$[dDiAbvdAJ9C])oj.h`t6JQ)F?.CuR3U:]hNMI@M%Zt1lt%YltJLOn$ng7C*Ds:", &
        "$Zw5w@Bq^`?TgmuQbC4gSDq814XPVa?EB)`)ktfVh8K(>F=tKW#B:38Jkx)n?QqDv/xhQ+e)Ef9uDkJqSS@V/x22MY]?470A>/$<;5UNLw^NsohW@b^V.v", &
        "Xp+>e@6%42K7,h$Pp6Oq<D(1yH:--WPw^c2>=)e^cgj#U/YE>=K#T^oq]S52_aR)Q<E?:2m:y8`5A`ZV6a$uEs8vNVNI>h=uus=>>HIbb2(5w430@[JT8X", &
        "@M@epEMo@ll9T:))0^5`s:sTHpDWEY.+u)1.+Ej,b2Pw<WzH?f;Hehi.36Y9otlf^3%LqVKQ)Y7zGnRA3of@QtJ02v:?QvNXJ_(?dYT9ZzTszLtIs[1TpH", &
        "E?+I(PnYukP,1_,iU%4trqLv+%NG>bKwy+IcvE$T;X3Tvi8O@_J]m-Lps`z=jdqeMbq?3P_>bf9;j/qj+t2qKkxYihr+jZ%a3HC)8$#dfdB>Ehb/*+Xa-M", &
        "NPyp?%P*i3VKfk2LchZc)][FieG>>?;rl]LhX,6EVfB6ln<4io3SCICm/Ji)NW/-;udu^C88^4CUdJ7V<(:SId0B^Sw:@.lkn2?c5^Nnp#=vQD?JM9xJFh", &
        "t;@?R0#_?w?pZ+-An7ctJ^[1iIS=dS4.;Q>?$wRA%1::OXQF%VEcs4ww[[su?9kp:U1uTETt^;UF7Ps,JHp.0L03./zy5@aA>oDC0rkrs*4Hw5tNIkkqTz", &
        "@,5j?U7BIn/l6;vZ.u)2f_mh`JN%,f(FwRJBY6R`K#X6?P<gxp>w:`J#QlUp7;E4$pcG2Q2URI_rF;XC%[,Y?Qo[sEhhuOsGm*8#^0Ch+>sx6?Z>*GMSem", &
        "8%XNj`s:#3*F:r3>2i,/7sLjb2.(DVWLN[,MgMR<UALu/g,RjCXc0PMY.4;;igi2du8lJ?)w-)r0g/cP8WPX$1bf>,B5;Ue1dJ[DZKLw.(I@hcK[%]cn%$", &
        "ARlvi2Mwip+WzxP1Q)6<.I<3q;kA)LztuhZu%<ptUc1`uuZx<gBE`kJ0Zf<9g5Kiuh4SDgL>I.G+m6g:;O6c)ta)?LoKkj7)21_EE@fO:+h6o>Kwa-*w??", &
        "$.l:IjD^MkUfucZFeNg^QD=y^.0i/+;LlV]6*7svf(7ZO(ufClc9qgpx1pPy8nFY7d$>?vvXP*t/Of:PJ4QlHu$`3^hcLINgr97`[=fCNAMz/]:Ji><0w)", &
        "+.LugKt8Zy%W-s-y[gpe@Xj-AqR;gDf?#D5o]Yn/2H_q3rKTl)miO=tS*E6>Z.f[^FNSJPp-k5/uHf5c>y9FMfT_[2^pG7^xHe:l?v3(2p$b>GfYNp<*Et", &
        "<Z2ommXpzuEY`_EvM-hNCcb0]<@`YJgR%#le50d>,+frzfT,FH6DgMl7Quz;>qD>(.u3rtXV[lb>fL9H4eqsW/>9;i%xjZjOGQX$Yd#,u+JM0.cZR56*1P", &
        "3SXQV+C%pP92Mhze,mfOt,@_K[vQ.h;eotldsKk=4T86<c)Kphx91>=((/vx(Qn9$ZHdonjP_zu3Aunp9%n8<GLG#aM<%PBiJ:Fmpsx-cPW,T6ZQN9Dr)#", &
        "Vf:/C7m,?NS(o_1Z8nS0Zv0MUOx5MWF=qfAPbAqAUT%eIoecCt$U`QTJ5g6x1W,uLEG-v$Y^hm%^^KGL.xmy)U8vZ[F%Ny$PtEwIIde7;>B.4b_5pK1@(K", &
        "O0?U*:HI-SH8YNss]KN>djbt3trt+P.9knaT.rk1nS[%/>;IEwOZ(4/wJIb*ij_OvTmgt;j9Bf*Dqb-7jYUX_J=3R::cnY%Rx-O95-Q2vP9^x@D#UpH<G+", &
        "^O?%DBg?$=4s[2Bb%0RnPACC8Yb$Sg?*ylCi)aEP+#zPKbDG3^#dA0ty%nA^mOi9=L.a4tztzge[649Za_os2(8-?=/RO%rbS(/I;ufqfImm1`cUb*on#6", &
        "Mbc6,3^[H31aob*YP>1n2oobSh:.ad@7y:qZF_p36H6iE(8[PN.jFV$R_l->oe^X2Dm=E,f`]4J$AhvF66lq6?Ft(6KOKB$7E0rm$=z]n/JsLN#,#=>1mz", &
        "uM6;3lDByt%c7CNW,fhBqX5:_W9lcN*i+LQ+-H1rc1JCjP16E(#=O^@v:5c%uQ_sQv(Mz<18plucHIXvazRtxoS@q?h7-`U0Z-4,:sHt`m8)vlT1X.Kb@S", &
        "seT)ednBvBmDf>`hSz:NWocnk)bXuFC*0I7MM:ENmb#UKgF[q/l?>_/?u]OXVrAg_u0L5.-NbuBpp?s##u.kN5zj<:_vJPv@l-4S1OX[poRk_EP_Kj,d?F", &
        "=pdU%]nyaaL:]633ij>iIH?Hvnk0A5%q(,cB%D_mzP+4fagfR)pfIjsiR+Nad+m0Li:I=yY+Go>OuI6E3Qj/7D0Fm[Qck%-OP;qQ,$wdSL^7E=U7(cph#K", &
        "0HUnO$ZKJv0L+a>>wdOLbHJ*S@<XGp=]?4wE9j?ba`q..E-uhT`#N7l8HQ]^pRc2m6JlR^G/e=Q(HV(1Ez@Zo)oWORt.3Tq`S9BN_*jd,xhGQPKEdY>z,q", &
        "TetWx6037Xw(rGCTcT4=_L]cmaxOh[Gm+AKN`w4$Nwxa8ontx[<NHg)/DL8*QC5cB#3H*?w$<MtsC@O_d]ygo25XIXHmmJFtEXK.$HE_N2[IXiBN_*rd+U", &
        "/Ni?7.T,Q,d4E@)LA=W%7OI;1Q1bQ+`w-fsg*dVl>b($Ilzbli$9rXjEk%jtH@k-po$`w*Z4%4[#ywh;knuF8w]nlvTFN;fXFnZsYS$>3mos93RUnxmJz$", &
        "#GGb$z2Pd=SveDIvcKDLg$7-I(J**m:(uo]ldQUa20*P3hAe(EfXnFf6P3?rOBkgVRA`@$z(fC_D$NWbX-_30se5^d:Tu6ahiLD#CQOf/o*SPaFwOOCej1", &
        "d$<GDfu,mPl5P5IDmY2/aEf67s6B=2,.Gb%h=dv<p,a+q]O[eW*`uU6)miI3f)2+.m*wvF35Nf+)#k<RiW9cq7@D[9n9quZf8`]`QI$s/n0%H*<NN<4?KV", &
        "%,^#]ts_w*Ho^S[?NES=_lS[EHPaQCN*Nh=#$yRg#U)$>@42O30IP:a_*:Kfqz06cNgU76%`r^m1H15^u:GvlkS@`iE%hbpyD<MHF`tkq1)0T>uqI1:VU/", &
        "Whu?i$Y/@+i:P^FO.KWU,J4YnN8Pi/M;yPBJc%<3dU+yV$z3yffucTB^@Mav7J0a+(zn9O-(0`vAP.To35apB@An#$uW*oeK9:6FR(RwCOZ`RKR=w-:#qt", &
        ".oi4rSS<@UCO+uIqf`6UI0)HQo$lT%B;;$cS8jA%@mq8+pg29t/c6E(nJ2BB1?kmFm6TJt1(.2o6bMmVWhG`B4*@Ld%L.5R;SAA?+QPM$qD$C`$zXL)Gz,", &
        "lNLhW:`DQFCDZrU3(3g>:pdv12-;@Yx6,nDkm)5*FXrddC*2.<x]S9M1EVAlGDUQ2.r-nG`QA/olX.F`j8PqHB/,>o,9zvc@JJ4,r/QX>kVQC)lag^f=RT", &
        "E;^[eIo=f6QGVNI(#4?h0)/=FMNiuAX0KJ?a;=;RPf?ION.APP_=lXZWp=q=A;2ZPUdxF9436o@olm+D;eabRO8[6YP#:pe_SSST)#v?q^X4[WcDuob6XP", &
        "*t+Of9nz%Xzye$:S(O$N6$Y2NTX3/0PI-=[ClMR6lbsbbfOI943R@u_Bj>+rIAiAR,Yr>*?^%-S[Yn5guitiluKQ<-9nekSA)cqZ]q,;EeQLYi9tJW7+lu", &
        "UK8T=(i5+slE<QW(cw26gi36y9=5zl`_f[d[RDLt0R5on5%@ty?No*hN[;CuO@@$1]9X4RPap;IdF?;2Uf@viN?=,fP*s%)sT2N@-[S%#8^LX^m#D=9kUb", &
        "PaD76vw3mkl.v#oy$g2JQGAR,Yr3h.;]-ZM0-5guitks`-V0SYu``Q]AJ2g*<AD@rzP2TtpyQk0yW>V22Qd%S)]sS-Of$BG@Bn?.)6R$C8m.z(siUqqd;e", &
        "+QHX`4@Ki*S-(Q9/N#$^sbu+5,aHM1NJKdGEWOE-z>by1f^VuT#gkWTAZ:C1rtwBa4@ud$(lH/O/DD`,XBZ<m=6<dNN`/HlBLAf`iGS%NH$vOmu0VYCNuh", &
        "A:k2^79eC;Q=hp,MhcK0M?2;@8qDFhu.m9HFM34Jn$Z-PtP@=]PN=_(b/j]Zx(l?$//*Mt4mfOt,@_K[vQ.h;eotldsKk=4T86<c)Kphx91>=((/vx(Qn9", &
        "$ZHdonjP_zu3Aunp9%n8<GLM:XL`hiJIhW^X_)R7nyC;v+cHfqMH(bb(iuqq*Q8ULC3n7sYw5=bCjIZcR(-;(C3X$;W3aqy3ve_^>Lza@Anj0i6s1s)w[9", &
        "89H0qFCDZrn>DW81r6_x<D3xt6JMY=XPtN2GdE@*>fmK/Sk3sI(,H6;SdBvn;BQ-.9e_qzt2l/*<<s,?W`aF)<;5q#Wc`GNM5K#XA.6<^R-::>mqLyB[O[", &
        "jV:V.Cj4d_H4MJEJ)d)4EdB-j+X3Qarb4=>IN5T:6DLyeJ3$EIiN4fR^,U2/PLji?=PML5HM%%lHP5GVAVDF-$X6P7eGKRg=<=9>de+Q-M(XY;YFIf[UpD", &
        "e0QdIMuc>4Um5htfKzEkJ5.5#qj0[R[fyZ>4<NrR6@bp(19Xe.=(Gndo9s)?urR->iClISdBvn:apzv[[d;57oA(,+Sacf+HLbv/XXe%<+q_)]YL.osFKY", &
        "ifIxC$8m[ffXXrz>+O3a.9$:2gKvzfP8Y]90,[Mx3byz:jEi1)b05O>K@Nye%vD^T/N6;5E%)oIS,[,n8-]T#6KQ^Befd]UA@*iK=-`4hlA_C.Gi)5r@Yz", &
        "[kk`N3mMS9HMg[Uv8n;[FR0eyS;ywC5)]4YYbTw6A,;4U=6G59yxNp2bgF`p97x(_F:j`gq(G8zU]DgR0:]ti^QT/I$<*?N;?/;#bFG@#lEHtoMtt?N;?/", &
        ";A%OH@#lEIIpvS<9tcKCi#f78>cD3s%PhXr+_3g8R+Q$G)H]6Nk?Haot;O(uaJfbE3__B7uKr^nShyg6sS5wK.:ZK8=BXo(fi2A0e`,Ch/jti[O8tF)knB", &
        "Dc_kg,B9#EE;P1Z_49:=6Vw@/H5.eMjO/_RlE*eaamucT?Xv*4%9>Ubt.X;L<u<#^BL(yPU(cZwE3=W<u)4uy:?UxBa+4Q.h9*pZY>.c5jw+v50[XqYC:4", &
        ":r6IoRFdKnyCe^*Ef;Zd?[_^G7Ikln>q6>NSlsFVMRXhY$kjv-e4_J+JM01b`-LLwA;euST1Bj/N?Y@-@U@GP_nud;%*vx*N9:AD<jU=Do-R[4E1bIZD+H", &
        ":OgBf6CrhG[WGjdy,uR;`aE=I]UmB3OtfKzEkJ8Q+/x1EGDkuv5oRtYm(cRNZ$na#m(w^l,QE[(rG:>]A#j+a)(K731AR,Yr3h.lk-ZM0-5guitks`-V0S", &
        "Yu``Q]AJ7s2xQD@)=C2=$MrSXgkN9vh/B/ovf(R/0WxV-t)hvrsRiM25^>MZ,B=v;+w_MEa+>P_D<+P-AA]_%q=Z38W=RZV)Z-KaiP[-aBLWgnp;[dA/q.", &
        "*oVfjsH^-lS:lGW-42[pg)njLKH@ApiFN>7.:xG(>YUWoX8zAlY)sF%/gGTYbkKx6e#5*=laga*tbyuSI/c9^.kbAi`N*BVp>f/cu[ar1$VK_orAtF.O>o", &
        "N?;tbG3Do:D8e+W5UId*m36h4.]>^5AP5E>s1YL(WH3t4WTC_RZpNYUm@`gP7TEbI*K7MM<%cNj-Ad(/h]uxZQ`*:)hv/<yS`pmV3j7ZT^.j+5)v83m;;W", &
        "bCb6u]>%tZ2rmaFS41Ashu`)`Qn=xP.3ZEi??(MRkV:aDqrYoXxPLbGN_Tfwv2DjAubd3no;]$nIGjC/O5_Z+pjtv(Ed86B,P+,3i.<QAubd4XVs8P+gm%", &
        "YYDf9]u[3i4N17DVo@U2(I_m9^1h5lhm6oBAD.V+;Q*QXCEoDef9A)n+#C3)$L<p^h7Q#^WkPZ*om^Tvq45i%#X3NIs8zwsG%%=rb7:;c34u/]5o6UfqRL", &
        "U?WuBUnTdA1)@#tU@Dn+A7mAudyfDV=^CNX-f;J@A8o1R]]7%PiHpcouctNT[3Q+;hiuNn=FOa/tW)h0<N?f<zOsBq:7.9rX<fMNcyHw:3Hx%a,=J_mk/J", &
        "6hYMR(0*T$DaW@be7xY(7O0]^HG]Qu?8TN<i,Bw1PAY`8Kr5*oOLiB5s$zqkM$9bcMMy0Yi.;[,Cbo*=?GRpq6`a@^r//JlOD5](3KXNwTJeF5DAk38@i-", &
        "*Ne]Z+fm+*JP_ik3k3mx2F9$q9veKEw=.FqEbGyBgauZ0eh4.H`6:l_L2s1yPJvg=Bl*7#3p`+YPcY2%5S6(7<9.D.mxhvfd0+K+00Dkswj*BSw8EPuWf.", &
        "9MQI^:u>/*[J)ZLzk+AU6i`W?FBcC0nIrg2,1SP;r-j8nqXel]24D8mOklAQov639>9oPdJ*l@oV+d#dJ$=ZEJBl/vX=z(#hUvZQSxdOBam/q:uw74sg4W", &
        "l.jv@L1Po(f>n<F1hyq$wI$ik3%DmEZOewVG]G.Co*p41f:I<n9+Go$QW+QBV3jN^+77%AlfdvE)YFO;qXnI+J/olDy3A>a(O`>.2-ng8>R4UG+IX3lA8@", &
        "To0#*[`+MK,=,%UCa-N]Uu6.1HQIG8ZLm[YTCDFMRznQ=U)z)<ajd$#W<pgqt8@LDyC`$%-y4SV(+[Cq[0RBBV.^#CQe^4Rb#s.P->+1E/73^^^_=W8$Or"]

    character(len=118), parameter :: BLOB_ROWS_2(100) = [character(len=118) :: &
        "e/HOxQF%IvOavMyZ^aj^%af@.AiZMoj@fk*po4*`Ae@M3nJW2+:joJzo)Ql]1MFZoIkwIeC<T*oNe/73/P,R@gCuX4>mF*$bli$9rXjEk%jtH@k-po$`w*", &
        "Z4%4[#ywh;kz)xB0]2e2-t)I=xH(xh3q6:zx:=.qwC%;5`t7zv7C)>Zw/M6Qzv1)15$oFq,>`+^C-T.%qvnWgAV*TmH.j,aagGo9RlFSWQ1fKVqTdbTXu;", &
        "BWM^ENUpqZM%Loin*`XtDfc>$X(d$1L<%`Vow][@A5e;vL]<=V6DZz)-_oj^WML.j7]P6WM>hE/s5K2:BYF(LeblIu.:q-e/;90eV^Dx:.qF%+KzjQlczt", &
        "5u(jMCY:STARMdRb1sD,_,hrnLozoe>cJPt:nBfHW4Q(TJ=-RG_H<g1J?A;AT/ApLkN8t@[r=KcL>[LH?7uLAC@-*@ojQcGvsB`5G?AvJ0g?,g_o?Ic+bo", &
        "RF%h-C>4QeQ^0G2)8_e0Q_+o9$U?gVg617sEsQ+O%ubkV]Vq#Hg.+l^.u3cT7v%94pZ>jx>J6FFLf)6HR.Okn0_*[->_2ihe68fQIPoFJXwMckZU5?(aXi", &
        "JAvxnf5kqb7Z9hxpC0U><8s<Kc20+MT*@eM1N%%9dSCKrm2%,h4-5kuwy>SXumL$XqnB:<(:?IlD,5g3?9V<m57`ULvGGfpaSja:dh99icZ_uLf`xvJ2pN", &
        "hV%=dE8-^Oh-6s%Jq?Gv(>a^p-M$Xv$X5,fAU9z^[)nc/aQrlvp]#:CKbeX6*)bXBrdu9+yLnO448_hYba:rOfsEveHF0d<bnvtQGmOurz4m2%,h4-5Rmw", &
        "y5HIsRj6u1VY+q[Ez(>))w1IjjjX#KZVdjEczzb%6+VdGuy_j7GA$9nMhy*CV*Rdf^yJcv>-+T%W72-gc+Zm?Fg%o0,_`<C?QczpYQ/#PTS.6%0(S]9ccZ", &
        "J[[f$Z/%99dNi>F@t0ePc+TR%IfMr<V0IwK[VP9bhDL(k/NVD`,5:5)#C<)#J1PK5l)<@?I-EsoKq(rb1<-9nekSA)cqZ]q,$]]H;Yq$Q-qoMx`HVu4tJK", &
        "Q@vGpTXhD[/Tu>6YdfNyj-b>X[8XX78_$YHb`w.w5lba/SzaiCh7=HLGmanEy+4FY?.7-S#%V(*k6b(uzCyCS1r9H,<b9[Yqq*+GZRHA.6<^R-::>mqLyB", &
        "[O[jV:V.Cj4d_H4MJEJ)d)4EdB-j+X3QbPUs,^jeI+TOj%QxQ//`AzQd8x#5TGFwMv1>ij`4,A?m>=2<8<Jx#GEm4vM9>yx<0QT+%6s,^b6+WyQj%Yp>%,", &
        "tUV.?0JW](t`4)AXOJul=L)8vHvKxl^B56E,T*rKIM*seHG;jrs9AkMryCy;k1or$]auR%I5Cv+kCK2<DJ]m3Kfn*8mZu`fesUfj;W-D.zGhtH844g5LFa", &
        "95fc@qdQmYMCoWRp34AMw:xzmEXU_`#[sftto:JKGy(u#O6?dJ6:_X,hDh<b.<f$8C;gMYLVHG^MK4OUNO$Sl][hQa,m66RP+UfvdNL`DVIfim2<p8*5%5", &
        "8tJCISftl^.$j_BZdfHNeG+V$YEasY;3+vL(QXV$Z1qnCnURyOY(YDTE:kj)Lw@UrlM=xTZ6]^?EVt0@,%nq]h%d=8V>+oyP5DO,s_>6D#/#Lwc06IWNNB", &
        "wkbNyDYxFMWRCjkTu6-CP<1P^AhwWj/j1upTCdX<zb4qCw$FX<z6r,sk,1)xo6u8q#XSUpAgmm:(vY]-C`5a2/hH8tJJ8<kj:hHlq>SXvoNSd3=;,kMc:X", &
        "q[;By%:neb%`p7>O>qToC3Y..<kj;awZ?mvNGgvymIl7:UpCXU#^M4I7D)5nPELN_P7h9[K`hEPPwOo8dY]WcNX9=Z:TUz82:tZC52YHj80v:pkL%SUgHx", &
        "x>6ZG%pJga](0`wE3OW`0VPtJH(aj2mPfFOq:h_kcOrNx@#C[I)bY1igA$q_3`gZ=P1igf#jS5NefkSA)cq[U5kFh2C*FmPda:)?]^@x`SMrA/T(-iEfeC", &
        ")DFp]fD11d_iWZ(40F>oi[Yl#P64L#hYhcuhOGjC>Abo5o-y`u@/Kq+<*VS[OR[XeV+v)mMSq-4LqyPu9^Z.wOBausfJr-*7h31)V7N$TZ<kng$+pODG05", &
        "r%gUxK[@na0++/]2Zm:Gn<*>IxY^x(OiM>lcppLtrtV)RNvIBAbwBz9vc9rrZcMU0-N$z*wN8O;upBPiXO3YMt8pMVJAjZTM:b?tMhi,^1*M..H@.UmiHO", &
        "J#[;94rr+W@WA5<ptmDY-sC0igB+^gHg30.9mS1@0Wn>2uN@;)4KHX;tqC/FK@5KWP.FSWpFx$cUbzYl/Cw(*RA$SGFu,=M(r?uDhW/oy?2qbVKi?+%X=,", &
        "oVio)WXV6qctdkE9,UQgbeS=KC5S(]XB9h,KWVG-;ynHdwin1.^HmbJ$`:l(M*P-[=hwIJw]U?J#7S:%tarbP9pJ3t4dpGV1aoyc8s+aS?%+iw;z,PMZov", &
        "#VP8vjb-n*yA8YU4#*x[2`/]67nf9r4FE1>qOw?GY2.z/>X)yT,;s#AU^s=f9l**Mfcn]_V^XV9m5*188Y:D?)VdA.Pz0``10Ad?,v%MIdjd@FmIK)S_2T", &
        "Sa`:fsdAx4bt*I;G2Z>$NeOng=lif)w_Jq*Byt2:7Mkfe$lgr4tGTtifD<uv+8o*D:PUMgec6;j83fTKtTcT1J:t`OSYdK6xX6sKI=q<shzs*%Ys^rkzb[", &
        "m?%$3%-`@+JXdff,n5ybSKfDb:75s>WC,?Rj6+%AV22n7pKdtV-W*p6M,Pjl4)YS-o*YN6X7qdEeBx`[VIAGxZ,;:khnv%>mFYy7Nf[bahq?J:9Kd_TKv-", &
        "Ga3keRGbUctPxTn`gI?wDn`%y*7C0P7s;q5pZ`[zZ#xSY>dzeI@e<:C#,scq`8,Z*4O3wb.Gxg9V`TsTA,g5@$jfHA+e-oVI8J(N7j4>=BiW7HQAF4vF$h", &
        "h]_Q7QoV[E<*CqimnGd7qA[RY;7%hvp<ei;2=tnl>hv#9,j*@2iIkYO=J90R+6:q4PJAOtYZW50;.hSq>I61L1A#uA16j3rd%ErY/Dmon:m<*^o>IXX/;w", &
        "yE]`)Ry=h3G6=z:@GR-5;jNKfkFQzuG+S6P[2N5KWLPU%rmwBg4foWZWl-Uik`/olK0p:UvFun^Ql#xg(V/ap^:A4OWBtjD/xO$/=4m+ZVG/ovAvC2aZM$", &
        "3$pkfLxmT.dsf=V%s2@w%q,0Dg?1bYW7@OXu-bi:oh80,,4oAKYy`J;)>HT#VZ(Da8Sg-VBb9D/Rhx+OAU>wdE8y7A@u=]T8B*@R>)`nNl>o>)P.LFWor4", &
        "05lTBT6+]LB>lF*PhEU8C$KeuqY4-:wl7Gn/tgKS_wbwGm@=$Y:D:W1PfZIKsb.F6CQi6x@OJx[b3J$@e6SN^Y(AqHz<MlpLUp#XGl:mig9-@%CG*KQ)_,", &
        "*/39l3;K5[XQ>Z]bXYw^Y*l:eXBwp=b]?W+c$^*VbzQYq_rY+,9:C723$EK%](K%bdxcSH^Ax3d26Uq[<Q%wth[_LAgvWnDU.$Q%Lq:>7_Oq5nJI4JI,IC", &
        "oR99nDUuPQnllIEca,N;6?T6l4.:zL;insm%KMG7c:8U1#h.FIOL0R<)l.-:7yqK1=haz7[q*3#9rqz*7`(6yDI.T1VsSjUDV@7M,qL8$PI+fJGgu(qQm:", &
        "%9XNUo+Ki1L(LCGC?qa-,ZdI_oWG-m6`ZxgGD*`23T`hO26ZHU]Lj<4W+.@tbpHj</cEcy^hj+lxo1;bWFEAysYt<M8?0C+KO,/L4(A^_wxnRgfcj:;-GD", &
        "G6=WBe5xeH[h8]b@pWqTh-:J*=qIW5JPLopXr+50uaK$NH3pgOAIj+Li?9*fJ%bwNA,z7-7_[O`z@tUI+r-:DlPLIs`BO4`>Op#IC_?Fu_4-K/K`_-8#,*", &
        "G*50^^R*nRi8oxj5Q%4N]sC`<5:3*jD.3r2Ak*#p@fBxtN*4M[6#aRTO+;W2YOSbbtrQfe$PL9XJ.qe[0f5WW/b(+hyql]<^e;?k-Fmx-BfAr@VC$c+fvM", &
        ",T[6-Je=ubOWb9wJO]Q,L^m+vf$B*AIW6X[`BfaPJ^Qa;)^UpIMuO4Os4i)rDN)Iuoyx@dHsJbQ778n1zU>=Rb2t@$#T:si^dw:LnTOG0`y6ku]1_qFmb+", &
        "RFS9.,s`)KE?(.jm(lc4EklH(%e)_heU,IS<6lS.0[<rd*N5vpa#2esaXJ8ZRaOD3`1F9.+#Y,eHdAN3`/W+=uZ+lR4K(Eo*5i=q#47uVj%EBwTIOeTf*$", &
        "WuL>(bk*]Kz5-uS)RIZtjOZD_u[tU,?#5B_@fPE0QN,)0Sj;U@lgqM`>()/iB1$:(OuI-+da,aYJ0GTA6isQGqQuM,-qgBJH#h;1F(E6q$U=7xJiI17QbR", &
        "IY_.)X[<v:=)gWD<W<-=MH,8#4N31#pInbHbrt][8D%?eNyQjHraib8?T4X<tLARX[r(EcNTRpE+Lh.uZHN%+-]d@0g],LZ#O@1bMjR0@,D)K=JnOd6p@g", &
        "FOestA<6=gy#U[>u:Pzw0=PgI(GD=NGmEog*j.b_gQYDwm(:OCIWM)[U]Cp5dF?-7Y8SW2J9H[BUTFCY0R3D.::O`qT%rck*h>U+s%bDL:AAM8mp,iC_%7", &
        "<T9NVmDz5=?<tme1Up/X8#E7%`Wp0f:XC*$(<xP@.8qS<Qe_Fd(/U/n(I$U$PKf;seJ5Un3ti+=jVpH)PM(dZD/XeLZKRdNZ_jp%U>x-#wte@.qbo$hCl.", &
        "_:c2/$KvP0r3z:wSu5n8pAk`CRB0zgk8V`^Yz3gX>j<K3g7wP<$vB/x_mK6Yv[-:ZRa4YSiP;(l)925%.ckewSzn9lgts8dOg46cY@E>x.QOlUD-Rt*YrD", &
        "lbYDDY8CIMK/iJ)FOv<-QEPM-1^[sCN`nyCF$V[]gNER9Uu,vyftl22[V`-EHhWuCk7MVYR,9=i,6<NS;e+.iN-0I;9ob_VPrL3zzwPQ8KW+Qi95E8jrCd", &
        "#oKx$>Sk?mg7eb$LBYJklZhRf$jdZB,R-%#2/rnTdulrDo9ptQ=Gw#n*GnJg/-ba$(WhH`6WDf]aV<r%-$rBQMcXfwAV0bJD$qxg0Qy4^.8V+Noi4t7Bzt", &
        "@R]Nbe)yA,de[4Z3f9UqVcbsM/3Tt8I`5nj95F>MOdAbVFn$eH6/)56k)Q;#%7gv(xr]ps#)ufXn0MghOGod:u9eH5d8u+hj;5x]a$MxU>>4Qt$#Tkln@<", &
        "zo80Nmqw%Sj,MfRBMLE<:0d-E3m]B+klc-63@T#Ym0.S7sw.UKfxiGt]T;T4^gelL2$Ela)8wJD>2/o<k4*9#GHpd63:?Xv>cq0*^yHSy*)5g%+:05t_Zz", &
        "5eT-O9kxP3JUDMt=94@qp2XsOPn)IgR7q0ZXLNa3M$<rPp0i#.QBEq+.<^=WlM8w#s^8oVeAll_m1PRh<8C_/[v]pS(=Z#v0p;74,qk<P1O9[vJCs<y.#G", &
        "U#4g$b3S.Bz9IN]Bv04;G:$/YRJ-uYjo<w;1_%-HHf[ef5UZFx`qPUV6LDv-aKA?6X0rTo$^YUqIq?(Y>e(pXYxeBk]?,Q=62Y(r+I#cK;5dg^GCf,GBw*", &
        "j+5O4UGTSUX]5I#LWcT]6e;b.RxxC/g_FtOPvqltFSGbO.:[))%pUru7Tk]w[v9F/L317rVV+LcT?GeI+R9$%Qxg:n$2uaML`BE%URm;vu2U9$19g_bgGu", &
        "q#itE?L4Ch3F+?T%E1tuDE2oC+9H-=[enEzHcBKR2h1(w%@+vxteQw<^sVznvc<;I]mOYdn5gf+0s9jK[O_pTj(>XSe7<P3@4TQJ1DBj+e]qhiaw1>O,bz", &
        "n3E9q]M_]Gx3<9dJlr9Jc<pAqtYt*Q[GefXCuE*i/DM*2u]ucw_^0S>m^`2N:k$N7J42+H]G3%>RGrCp;lS$XH-S#Uq0Y/k)5;MG?9yn^>D3/aOhS?d(YT", &
        ".)#5<PH3F@=5xHZ^DjqhF,w[[TS`r$?_VFG/nawQ)CF#naQ7R:<=>DQOTK4uBl+Sh5-U#`0_6hI(hrO>w?=n[H:0=qbknap(V3$85NRh[r:;/Jak-qO%bq", &
        "nY=Z6(v;i,@9,btb_>[O4Eo7ThEsSx]<#<dcKc9dAvmGu(TPhT<xfqTa;8O;ir9,zg-tPXn%?j_qS-mLySJcRglNz<,6@F%;*hC7Q[6H-dS6R_tqBT,ONM", &
        "Z=[%#rj]kD1TBrkA*U?klP_tJ8#HR_4;C+$O+XsFO()6CP%?3m((S99hWduvohwjKalX<FTju6V,->FLwtw?,?ecY)cM(cmr)>bqzyLhJS-Jeir6<B[xtG", &
        "]2T,k-)kCE289cab/6)DJ0:WQt1y+qH9=2H1,4<_<vh((3()Wmn1>EVQDo-hx/u8%KKeh63f1.(T=f6+J.+uG?Se:9@,/(l?/jLYQqD^Q7-Ey[Z#cH:hgQ", &
        "/,bRbz1L>_(#Tg[y^7Uny[g/ECKs9rFWuEN8mUN=]-5;P$6Lnxq]JD.%zPZO6]V.2fhzh1cOzSD4H;OSh8,)W[Y,:IlvK*_G=A33c0M`.I(m$0NhR*m]hM", &
        "X%3#-R*/UqeFY?](Q$K_;Gm/Gtm1oSCULA]XNiG22OAexvF4;(Kr#R4m#Jp9Z7^PFRs>P7-`S/pw8PYt#jEzspgrLnx+-)a9CyQCbx-v./N9^aP<S;qm]9", &
        "cLmOW4y]j)Uqa`PE?b:G4gPE6PA7yAJN^`9?<Qeipk:8-fj#okHrhx/77mWa/WePy*>Q_]J7t9Rt)mCM_c4*L*3]dviWOut`,Y)(UhE(sj?8-_0__Luzvg", &
        "6_ZFbwfx_df.yGR@h,f.x+X@8?rnox#R*##q#E:OR-[P+<]dtXY:AUng5s2YCYZ6*^Z=QdD:mtD:U,]+lFONKZm#gkQDE3P#UzY:S6;BQCakw^d0?YkOq8", &
        "Oqr,XNPX4y^FVjtN.xxmibGt1MY]QRndHIILdxu$ARD%;60)<okFQU`-nirinD6bp1.AnD2]M/Kg-Efd8Xs:dNXT3%/;^b(@FU4BK1Q4L7dxu$Ax3(Yxi$", &
        "5r=ujh]fpjQdz-L4fX)J(k<274:w2wt_,U/XD09q0#JhX>E(PJ[nYPy.IF+Vjy=sXAts*i])wVW@ZV:v-.ziJ^)dv*[;Y9AJGH*V=/_Jt3-9:<t5G<50Wk", &
        "AA1CP/htz=36lzTmlsXh;nr`N*dxvn2;l<UNkiS6fHm@z0AOxD)B)7/Nl+]zs7,byCM?aDFXAQo6]XKa)P6(<,?gqB)$fAJ.4vjUq`gwx:nu/A>-a#p]9P", &
        ";A]i_9ZY$+MIWROoun::Wn8I.F8EKBZz+N,vL8V-[I?(Fan`r+hQT,)#v/KdfZk)P#hw%@?)[^J@cMFi7J5E?]E-IB@XCP`p;%V*8`mP]q2).<QY%klVfD", &
        "LNIslcfJEsKyvH%^;<iO*m-$_oV*z*Oqq:))W5[4CCMJ4[6_^Ekv_b3.bW$>Cbb2JJ4G<LyM_l9Gt$^`iBLb(eMmOc#T4K./(MTO5FS6r;%dO-EtR:-;9e", &
        "3]Fgz,X::Cja3EI/TPt(,nX_rJZHM9mZ,,pT*Lc4j*b[0K;_P;X$]+ir=)@2W;[]lW/osVsn=wqCMR7,@_dP%1YL1DY_vC_$4R<Tt*bTHjLWkl9.4YK/<8", &
        ">tenQ$G%Wlf-#n3tp;t=;7+Y5twK0O^FO*j)@]h,Dzd9QU?d)PBTu1b%jTQ*t@a/#=Oo<ND3OOZXiVJsLET(wi1f<CYmfQ7PR8(o1QU,dJkP0fbp?51#+K", &
        "/u.@1_Y:<PCuORq?^oDEWq<H4#Nhe*OL)Rj:)4n)7o54I`XMf$vW$#3k-KTgFA$MHCt+OBf;>hTS<4Q#i.+%>cyD)UGx^1A;HsQTJv-56h%sMCcDVK-v+h", &
        "1>C#Z>9`iaK9bOA%otIRZ,>R>wCcwvanv)Pa[w3,b#p)BBB]5(];riOv%P^Jq[W0;T8jfPIIPUQ+%XW)f=?c3khl$OtoqyltsPFs2uh.%]*O;vJZgx2Al;", &
        ")dU-F.QvY,-K7)Hj(Q8n_=2YqsMoR`p%_9duA04eFRrXHb6@;oq^2GIwS,sPYdK[cAvC0Gu2?(E8H;QQMNt(;-Q4+/00M#l65dSSCByQ)?n#=)gFLia/pM", &
        "Fu^vjCEs,n]bh`Kio?jT0aEB[O4o^bA=F%Ybfigj7j#Fha?ciMaf_l*I]Xdum0EK9P,KR,JO>zsrKh;>4JD(w^I9@FY8D>bPNmn>3IuU_Y;rjIS<ETDN*K", &
        "63L@2%UWM2S;l_E@2w7J@dmt[fIN)$F7fP)7<P=-26:Z6tvhX,74ow8S4Rgs>ts2sMQv=3]<iMU[%bw12z7gK??>i^scwa@/NqfsY?Y)StTMm-;`@maVSQ", &
        "vVF+?$]DMgMXD>ghXef6AD8*,?1KTx9b;-e.]y8aip*Y[())p@*Nq`70G;U,SPsEmY$Z2H.bo+cO.1Z%CTIsw7NC$tO:X6AYbdjF3YL>f*Ee3I6cxDF4a^", &
        "/EI3*1.M^a1TC/BR74hNa?@:OOX]wN[4?(]sg=K59;N`(scO:gDL8EAum`0k.CYe):6Z7<cO*_:Y]=4w*$0sV$paO?l<1px_GA>.6A9r%`QI2X-m^a/2v;", &
        "w.MYsOyI18<.tRe$QDOFTD5`;M4Ik?xm6Vg]8^ykJ[$V.F57<$z<afJ4T.`^J;TbKd7oLqJkTU4nDu#n2DU+S$cqk>W)vB)LTGdT#-b:-w5ac7JHu^W=+k", &
        "<CTk)/S:Lc6c@b$=#:Bmt)5.3iOK$RcOJ)G%@MXt84@Wo_rTg)d.QhCP,oovfJ]R=[^a@>)/(_Jwtgo68$#GEg5fIa4*8ionfKiraM]2#N]Qv%*i2TsbmX", &
        "W;,;-65%cTkckk2vrc5Gk_%S4*f65[[UTu7HcRD//iVK?A0xwar?*ZpfX$_u1v*Bt)u9=Hr(W0mGli?SH#L.[iKI>^@_45Q:uPo%K^lC_Tfo7>xeUHeFBT", &
        "`g,;:MCA6X/-(0G4IFLA;rlBVOrBRR6,xgdZ:N_;$tuKi%7+cfm^jS]hWY-o48HPFYWe;HAbSkNbtV@6H(:z9+[>4vNxRAz4Og>E@Y>j2NIfE@CPa)t2>)", &
        "MPUjdB:LaQ6dSw(YUW98toe]O8A>iOC-Z1$/Z?/@4qT/)EL2^YpY?Gy%H?Kx^(ct8$I:LQvp`QLe?UE%@vM$)*$];7tgWPLkMk1ktT$XhN8A6$iu0Z6K((", &
        "o=AOa/3`G:fer%KZW9D,*O.x/?C_8:1uT_V1/x%C*Rh_1z1%cXMQld^xoF=P:IGnfZhK@,FUu*Auu#dXSRZ$l`s)fi>c9*B)WN>-M*6a(AW<z9vXDSl@h_", &
        "9/S?oI>MZ56EDOrF#AaYIpccK1b(y.q*VkJn(r?ue,f8>8_VE[sWr(+l9qfmMVKUT.C-^Vob@.(#ofBT0#`or55e-=SnPHvr>+e;I=Bmsn,hg$HOcqKcKI", &
        "@Pc1,zp8UWw0lsRp=$_x;nK9bDLA4#U;PC:EN-CfC9_#+HJ]2_UQc5%MVU-Qlp1WPhw61Ia1Wi(]zJ)CS00UjZC]uI5@lE0-Nj/BYGRgias=V3pneD2@;g", &
        "[o2c+fY)u%gcAE#7<N=<iIEAoY,v2^V-qTKYEr*[Zv[$%R]q_5iZtsb$-97%FY/e=#[fkyiP_Gw4(/q#DT+E]72SO;wAHe4(YN#7TJL:Yl]=/:Ndba;:AP", &
        "Re+G`#p/oPe#5om;fPfo)(I5DN91,oTFY8=4POSnuij2n<f$8DCswA`sR7?DPEBf)>i<cezsWP7N411;h_fU,i_0q-wASrxp6Lm@g>%+mzw3kxMUcbX-yP", &
        "Wgs$coaI0w`;A-pN.ToYl;46:Y[O0f`EdcoiW8hO.h@`Wi:[y%m:dIqb(fkBD#=y-<jtc4awov@O/M6C)n$fNM+f$Z%lj29sfLWr;wy)BfKoK*Uy-6#NoL", &
        "D]K12zP]F5;k8H`OE[QyU%=<aA*4WiHF_OA^V1b3dX<?O-$u/zAnO8Bpif+n73jrjCdWmLg-a-2sgFYIy`XhIIFNg@Qe-rLQ<l]A+_4AWU@/C/I0rvD*dG", &
        "po@]$QV-tO/XHR:a4](MrndFh2,^=`QRH4Sr8)fUpf9q.`_m@O2VwX9@=`:O.`?i*)w4*b>/ZVlH*?`*7U<)a.nW+A2*G4Pk,dM1),scC`)Uo$`apoS_g^", &
        "DrOROUMOWJTt-<7D13II%z<y^NDv?JL44-r:MzNi,GcqfW%u%_^?Cmg022*^ZJ@VhfgC0+2gaPWv,`uPn_53>a;DQ<.CqUtDkrX<CoyNL]il>5D>H#I>sJ", &
        "PwP:ysHc.MA=vjuH_ao^A)FnUV+Ko*TZ:uXtx`la,;6w0-e(yk-a`.:PU:VMK(1`@=9$6T1@@5,J%S*mIO1akBN56NcaJ,kn,ENy/jOT_%#R)v+=4*7_s%", &
        "Zb]w2W=dw<9LYJ<4t_V/Hdkn32k[-vyNWKEuEzx,w=)/Xowl>;<NjPP2$g<ZS6dO63,<K$/i?$OJk.M-$2rA-WPu?Gn9GSo*E;l@m>.A[0tCq#%nj4f?yf", &
        "yDoqc1)6.aYUq9zp?HIj]ZT2MVK^d0S.5KG8GQW)$W0/G]5nZ`m@hnpIkb;:gD5.?$EoR11:$EQQa:eFPhMu;p43@iF/K6`Ut/]fT4k>Q8uc;K:R^o*:v`", &
        "`B5YQL$v505^v/v[YJr<_OCl^>vR06A0[FV*LY-@d>yg$8_?Smr1=1]AXVI_qGy(o=9<Qc.q0$I6J,)$z:m<Hx5F-yWe]KPyst<hZ3-n.^VC)>XgnO*022", &
        "(4>5PSvo7*#M>JbJ19vBIc8$oi*W@D/rWlwtI851$`#OVh.K:VUSV8+o/eF_e3=8M<?<ekG=[@;Ot;(.kqhVKNeMJiSvaInS=i>j.vfZ)Lv_U6`^wMD+K6", &
        "Mb$ZB,#qj2ZIQcPp0D4ppM<N*Sq:wLS3v-kf9(y2@HurRlm+j(V2QJzJ[a2tekp_bP;pN8^G@63?[28aNSn-Ic;XpuY(sel-x9]KKQx<[1#x<[1#x<[1#x", &
        "<[1#x<[1#x:wHZ/g4SqucQyrx<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[0x$SLUS4oKy+d*wc[w*.xwN0RMOx<[0", &
        "qx<[1#x<[1#x<[)@I;_C<6*L?54Mm%MZy4tD)Dd>sx<Y5Wk3JINWhEenx<[0x8Xioj<N-)Ds6NIq$N<b8<Lmw3W1=L6#$baE/@[C@######*1_+4QmeP>l", &
        "i_6#0zs1N@9phXI$wq#####################7nbGcb8C;#####i.Yd3sJ:Q`*N9(j#ESYD*U*V/#J`1p#N,<O#Hwq`*^X:5*b$Pv5%^Jl?C>9AI_u%m", &
        "T#TlA#g*?:cb8C;###,Ci]lHCsyL6ot$q(k06vTT5Dii9nyB<PDhGqDsv,D0J(fE;O8>($YR7ardnnOGo4N=q$8M9T*1-lo###################(/=S", &
        "Jp9UGhi/=6FE###############$=ZM%####(E2wsc#####$@`c*sHRktsHRktsHRlbNL:C/#CmMj#CmND#HwyYT]H0]^z,Sf*[r_k*[r_k*1-es*g3el?", &
        "AVRV?HJH9$Gt?ni[.bZnhJ`8#hh^si_S/1+#d%;02+0y;#-GbE@d67O*Y<hT=ORGYIX8W^U/l9ddklyYKEX$YWCg#o2gNnst[lNst]RBt`6)j+bNUd*x[M", &
        "z*x?ag+dR)Q$Xjb@`5[Oe#oZ<A#ox4u#oZHE#oZ<A#oxfO+)O=:+)OnJ+)2um+)2v%#u.zP_O:,/Olm<0Z2Lt3$f2j<$i5X?#vowP#vN8F1/6bS#x2IeDA", &
        "aPs?5Wkc@Taoj@X/0T?6/bN#Hwu]D<V.hD<V.l++>C;#ti]R+1_s2+20Kw,,u+`+#czG$xVOq$)(K8$zahu6J?zF5OMF%5O*jS6LJ<J:]q6>;Z:ljO8b0s"]

    character(len=118), parameter :: BLOB_ROWS_3(100) = [character(len=118) :: &
        "?dp+>?dp+>?dp+>?dp+>@jD)<@l+4mJ/Z;eTK;)pT#TyBso4)Zso4)_UIm/Q5O*jd:^>=?################################################", &
        "#################%4.?=%5l:JetgpKp:G^x%>G?11WTho%CRm5%E:Rf%9?4Z%F4rk1O%.i%5rNb@tA89%JF^8PFo4XZtU=zez#Dop:MDNubv1F,fuiq6", &
        "z#-@<:Ez1FJ$qlKWm=VPfa]][6V7W[8=unka%ISuy9[UppSFO,hf$xpszO5<RFuJFO3#,p[,,TAbu%fPyPZh###?]((gKEJ/Z;DJ/Z;DJ/ZQg#ats9mzIe", &
        "[##########(+>$.Q9htV[UHc,fr%9,[ZS/7hnA)K#####S<t;a#####$;sstHzbp@####################################################", &
        "###########################.q9F+p#####################################################################################", &
        "######################################%SwOo`uk*(mq(%4$94oG@Fwtzo*bnHGILK%?S_@dvZdCdlS*+>.H?fziLjzl^IhiU$BZrP+,,mPg2f6h", &
        "RThhnh/anktlw=KJL9@mDx.zUidHLdgB]pL5rOmGe=.AkN<U<?(J^dcX6UK%d*FW?yYguW*jYeV=?Ufj<ifm5_M4P9sKk(DpOT>PAHRC$v$B`F>`ZUqMeF", &
        "`*>igI)cJS2[*>V?(^dL6;>7jnq=LM]_e455J9@`4wS4`%(8AU2nX/.KXJFEwgBO*^7TiLEc?(#iM7vHOhfXkFZvBg64@X9AdOt^=4G3X>eAAqm-#dBxC%", &
        "5^Pn$4tGdy^Md7a,k[bINhMO01UcA9D@7HPGihQqxC1_e-X4KT3Fd3B+vh<Y/L=I$DjeBwj:3dGH]yQniqeF8$oXrUeX>dfN]8CPMakK/aA4+pWvB2i6^C", &
        "2CjCx/:WQ_Mx(C?du8ZKxOupE2MzZ6[xk6IipPqI.yKr8AxRi6k/;vHKnkCS>XE@u6WK6T3wG`@moU4lvj3GvJL5olEw-j`DnA0if3Rv4M4L:Cv*CIN$GF", &
        "p2)l%tbh(/Zsxk#_v9%T^@P-wXsfVXK-OKg]S>%Q1/H=/Xbtd<80tzgqqR4?Q/=gdK%gFcGB0^kHPqAyDX>r/5rY74c:)U.pXsbTuRU<hqTTsrs/_d]vEl", &
        "+(j=:$OJC5IUZw1xnpbEo/%,lX4,O_$vY^^E0AUszkVJsq1.%2/5bY#Na?FPGP]80yLit_7lYiS;?s.4@.uR];JZsxb1T1SM`XQSF1N@_^mSN9Dkbq*FhH", &
        "$w`_uM_2UA5xaGr$%mYTCQ^8]cDFa9ycF%U(a>=;A8P?mV71.wL.^`mfdFrsWs#jwZ06lsJ9w>sDYpK8B9WJ4;IXTMN?Qb8fRNQ>WorOWS@h3rwpiN)h2,", &
        "$PQr,*KpqVTmsS,t.w`5.Kc7@Th>iqzlYH,ZbH*F$rK%.kwS`;ClYIR=MjE()Mk6MkcSK%>w?>v-X[qzXebJ,68A+]RS-L_^fxyiys-#TYa.w8mMg4*Mvy", &
        "TH>$iwnUuGr?Ywhq<rN9DpD[oM$HWfRZJX;=v[g1cvkrK$kWwZUCZla4Ro9M`f2rGQhJnWngQ`w64Eu`CpKHZdwk8.P%Kdt+:<boNS+wZUC]lZ;]eaXe_[", &
        "n>N;UEXi<3tG?jUbV=Y*8[b^:i9D]TqeVmpvP,S>KimiDM:S=#YXZ=tX66F.f4-L,r9]sZKpm0dL_t(LW+f%:Rr$1elA++5>JR*ktKWkDQygzn5hhcObBv", &
        "mDo:wA+pLR,3A4+r>tKW3HTJ)gwT@pplFOg,dCDyT>hyOiqx$(i7[+,@8%,t95i10qrc+uGj;7BK+DJav8wR@f)s,5nlqfQus4-eL`;/y=7u^Xgmb+LQkq", &
        "eVmivxES]C6S@IU2O?EK8#s#m;W9W%Nt6FKpm,4K8$)sS0tCS)hAiCRSSy4S0tCdS-Ihxt+z<CsfKQzo9b5`oqT;-B1:TlodnsjL`0Bajdnm_+qQMZsw,n", &
        "3Uc@O*`w64iCDIv^cQmqP1Vld7pRH(noqT;;uB5;-CA(w)M]^Y4CA*`dMjDLgH`]A<PV7ilX;uma@@`y7e5[,`m@]c]^T6y9<fnM@F7Q(]u^Y5Ec%(_9bE", &
        "?tPLK-T[rj?,Ei6(mgb$VnW-w,pzq+l@XB^eMVtc%gQE^oIgtr<)=jvdjbGCcrX`_-+r`#=U1uRwfprj?,EmU0O%uRwWGjUqo7ABAMEq,?^G/Efa9[oLz>", &
        "89J.p99vf4U$kfZlYGO4vyOV:a.cubMwEO=_Ot<aPTP^*m;RJQmr`P_b:@b9rK%.l)mEV+tr_q>uD(sVH_25wopcITNN^CVGvgs(:Vp4.T5BBMl[4)n[oH", &
        "_zlaWU8Y=Oh7>RBuusg)8ECg^a#P]padLJn^>tr8?]^@T<.3#s#)Y)iA=tqttuO6z^$(bWt+.XgXD@r*g+]96q?nWZ/cbOBqZmr`S^MX_Y/[iY8Bw*i-,8", &
        ".P%OcSL1sK8$)sPTOi+b:NVIrtUVfs-,Y+wZPl/la7BnETfW,H4j<:rtqRwHjKzluB.C,td2pMt+ne]hD=bh`w5+OFA%+hlS$DCh^+4)`w9thl(Na6m9b$", &
        "Gm;N1o`w9sxm;YH^;o#L`V$$uqlYH/^JIrO5H_D8r8<SC@9/f:t*rQmdm;sG7b+L=SMN?PnrNLDio9as)@IIMOvjqF8HwO`A]MwKZbnQA8]85nCTd[AI65", &
        "P@@uAvW-4*hbu`d=Jrj<;<deRjh:6@2CxHX@vfVv58K=y/tqwD`TGT38ZIVvG[ir@d)M`?LufhfN%eAupV1gRuewL]B`/kFVNrai]m_N86^_hgevo@.q4v", &
        "M][C4wZUFhvOw%6wTU/3>>[/SvP,U$9@mD69Mc=5vB+obvP,TZM]_f@>SdydcSM4vwb[Qu9/gZxfugW0?rzEs102+-ZtUkgFptpAR,+9>9CD-9B63c*_[L", &
        "KBvP,UF;^a-*Sq$C5VwrF3EzEj:k-/<I>:jWeBLUOCtuZJmYOfdOqK)8B,;3Oxh5ke#C%UA4l_ps`EC06(=<6HCM+kAuwQtb(c;6+xm2f:kLA0UJ:-?vX8", &
        "q3DiMUppxmI)cL_ZDAKFxhX66rPbNfaE^bFxhff6SiJ@ivU6%CJuxZQq%AqlX>`8>(<BKL;RQH02nI^RE7OW3h7@=ql$Ke_f`V$Y)hyf5=JGnrK%.lN)xs", &
        "1Hhk.;ww;NWl$]#RmxcA8kG/UC=;1G6wZhZ>uLhP2?]d@yffY1vjuK.`Qh]0oc92a/B9vj$][Kk?^oK]vQig*z5s)bbC2ZeS6Y.IyHZ-;77z:KWvva_Ob8", &
        "F]mW_hB-qq4=KEd<smN/*_K6khk=k#Ek@wLl3a;;aUGJq[X,Qf_^Is).tJ8x2R=S2YBiY^$g8IfKo`P`ZyWZuot)H>zsYq5Jm%9./XGvP,U$)mMEIU,3mD", &
        "cEIyTZtU<g=JR4?]^pM=ljHv%l_hFX]8zy9LQw?g<%/LJZv4uXwM6Pla,l@GWmDhwa,l@Gv^gr%Hs$N;([Fj53vZM0`@>r3LQw?riLA,<r_nuVeUzn>fel", &
        "NFoV-^jboE?%qPALFbnH<Ra+sRtJl+OZqPmy(;ni?dsG:`(E8D2Nk+hYYO>M*8DJ[v9WW.]#US/9`*tS)fnLX`N+imFv5ZMEd9-`5)cBsAWi2_5Cp[RyC0", &
        "5Z5i(j*2lmBCw)Hhe;u,BR@@40nA,tOi#8`NLb8qeBNeK+RIVB4Wd8Fd>PS_N(QUPP0IQ]+O2_C=YT0rTXx9e.;4M$wdsMa,l6$d[FPV3fl;(H1lGfM9/i", &
        "?C3R(dQYUotC(3))uUqFlvyL=TvyLHZZ9_.z@%NaKo9l]_uB0ff`y#15u@ehQK-S1O`=C;2;/vym@QW%0VcaDJw1(xPHT0.ls.kxG?+*l-`y]/:-tu$A.U", &
        "KDR,qvr3f(6+,qPduY28j^QM71P0wcxukle.juX2M]XZ=5>2L)%K5mlT9T43(M:k+Hsyt,*z8gON-T^1:^;a`ra,hV50%k9v3YwT..PXBXPPwI*qPUP3#5", &
        "Xj%r/6;s(ywS`;C1/jCkvwe>@a#%5Kd,775p@AlALK<K([V5DrLl#Z9l.9+xg:zhRrk#)%a%`axQk,8^Ub9dSvF;(blZ@1-mVw8ilYGpB#bM-TFZ0SNFWp", &
        "(jw*u[sT1fij^B$j)^FqxiLK.9Gtr8?][EX$<CI#g8Z291t/e`Q=c`:89vi;,p-vhSPK-S1O`=C;2;/w(CJl+A_b%Zp%_hD)Zk+2Z`Ce1=^UR.$qf5)mfb", &
        "pf_XKI;kH5`lsrR8Ck9I>7zPM64.EqDvwJQvz%Ik)*k[ua7@jvVtd2Pq:LH)gj(>Y4A9I,i(s1Jmh<`XXv4ZC6HT?X;**Mk77R)M[cAWw^-(wUQuc6b:@X", &
        "-pRANX9@mDs`w8Nv9@k^iboAv$)]):,+L.[x:Ork%+qT3qMc]SitRoY@MvTu*(/<]ce/2nk)3b8MDpONkSGQVx43%>j2.+wCekjr9s4;Zf,?K>qe>w3>*J", &
        "nqaqd`Ep`cPS_mw8J@]h+_if(_bwk$Yl@RJAK*nhS%@dt+CumsS]d.zX4Jv$]];vyXxbv$X-C+so,lRJ4DV:,`>$p=gBK`#NW%l:D*pMi1Gxpwkh_[oheQ", &
        "`i%9$Ql$Nkk7RVjl4CcdrJsZHm;MoylCmv0iX[bSD^:ky<lB5:IRePF8fvP=^R[^DJ:A=gipEL5l1(P:JWa1ES(tJ$.knd+C<)34@bI3-TA=EpcCNM@wIM", &
        "ook?(9RZ$MhpttK-ABcSIVbCB`)qQcZWsf_2=;zwcqRJ4KbS0tCRuRoObT<d6cDAue8<l?^#r=`-Gvs9y3^p69z>QCnyt*)71^Q`$*u`D$TUlemIa%`ay4", &
        "2W>Z:ls6CKMxIfjUZu%KK-@mwIgSaZuI0QW90aXSr?YhboELa^P`x4brid+^PHj4LQw@1C54DBW)1$uPDvAJCdh4>tR(H-0/`3k7F=)jAxYdWrL#Y/LD;z", &
        "Kj.1<ftdP,:HiX:KvN449eV7v7%mF08%iH1:6:8XYcs1UC1(ni$8HCBUq$Di]HS,Vvl?0Hd88xeM=V;)U<L(=-KE+NAZuI]<s:n(>GTzwF]+e(7?1R08m]", &
        "AUMVN%36LoWo,s.=SnGlS9)P[enaLD2qMcDi;Z._n+yX?Y.$nWZP$4-gdn.mU:/j.UiX8CTdl8mk:X_jAY<vP/xbF@v(ws-@4Edt*FVPTP^pdv$*Hk,dPg", &
        "BGze[L`0Bav4-3``z_X6Mm,EKKLLJBsf_3Bsf_3>lXOGB9#H2sw1[rBM#lAWb:>9Xb:A/WlYI9c/#6I:-?69$#V4BKKpm,4K8$)sS0tCS)hAiC]Q]Ego9b", &
        "5`o9as+C/ilyM#l?=v$]]_v$b6^r<l=6rN4yvHb`g#8zMVK3fLa_t$2va:6Vxts.WNN2rQt-mlT;?tGHM_Cg_J/QA<5Vm^_A4s)R/;vxXqhv4<Es$$jw9K", &
        ",e90t=XBPrL^mqb[YetBxbZ4KY_g/QlNo,H?^+)HiMZb[#gCS(hTE8-Zw%RP$NYO6YzQ^oxMxmbyg)6JZdKoa1aL6_KJB,(jts,^Q;`$b0oC%,R`2X8.P%", &
        "T,P`46VtU?tSDSpck-oYpI@CL:F+PM4L_*ppvl2pGO>0mL.%k-tA@@/,HZbrzI0bZ<F(My1K[;_F6]H):E$lKNJ_T39WDHp$_m6L$@IWvIFW65uB,^uxGa", &
        ">O/_5;9NsdC<$arOu@q1X@Ac_85YrLJ.3B7fcXf6h5?u[ogyB`kDwKGu?j+up<j$I-DZ@e?LOGEgLQ(@Ol6,Z$abA3bNWbpi17v[W5>c9l]int3pXvxZ<]", &
        "nWngWnLXXqK`N4pCQo7.vxZ)HLQ*y(X5j/EjIW4MmUqfJ;KpihIYv[GL^pv@.azMG(^rL@P%_8KmBCw)Hhe;u,BR@@40nA,tOht,l<zxubDGg-B*WlH@c*", &
        "Lpj,U?ph@FT9^Q`$*KSSK)UlemI`<jjQL#:qe[znHTAFwM@Z;pO0]kO[Bs$vWag8$*6;>lgkC(3))uUqFlvyL=TvyLHZZ9_.z@%NaKo9G:9@,e@^ZbDiIH", &
        "_D1#c`:PMH5TpcRt_LyZEmLE1Wj-q0h:SklY@Mr2`DmF.ltcZ=)zy;?Vo4f$G$N*%t.XB?V5vTcoCr/s0(H*ws(ZMPJi[=l/RJzjW1fX+94/v_^+m8%nhj", &
        "2LD9^lMwO6HhfX`xpopmmAxJRlqe].cj-<n=KAWV`q5Jl9qiT/ovP#`>qI8MFS1.Q-S3P)1Hf^^$G6:T5PW+td99pGE8Q<BB0h?P;8Q<BBbdvc-u_tWaX>", &
        "dfNPV8D$X>dfNX<300^Q`/ZPTP^[PV8CrDl7L#k*X%/rG[EPrLe+WU[`Iu`vqve^wnRTb:8MqK7xvOkxh2alYH,X^]f<-)Z?CaqnD-LQnZhz/#70pb:@e;", &
        "sfKKpuGCpLC/gU8M#l@mL_sdfUbM6lS/39s/#6VL42z,ajWf7]2xGACl[2DW^:9CxTIB[:lR[Z$l]n$2aYvE[S#H0SiC]tT@lQ0x$zx,GWAMFKnebW[fQ%", &
        "+8lEWc5l[j8Xpuw@gm;L1^*`gjL;32ZXe7SI/#Y/dOmIJ/jC-qdsM#l?=K9bApH;p;HM#l@mL_sdfUbM6lS/39s/#6VL42z,ajWf7]2xGACl[2DW^:l=em", &
        "Bd=fu%l$nd1?.Q-29vfFq/SE0t:]$]pM$=?1XVkv4D868.P-SoqgYdla5X^b3wS.=HWH_vB%?bK8BMBX=ps6UbMh6UcA*.Y]Dz8B1:Tws-@:jnXOGdA`E@", &
        "xHCV#1Y>^xQ49bZCcQiK)T;i@rad1ZLb:@bT^cW6Z[rb^C0NdC4Is=Tv$(]?.`U;N+_MaptanRNZYyyB4=wpF0],=h40fnOk3eYS;QZ`cu=ARfJuRxWXbE", &
        "?tP:9zw=i1K-^X8AeQS+?_)6+X0l[ckwslZ@1#s0(N/lP85o<eIB[(F_wIWMYze0_l2akvlhVrEYDk[0TbB/?MQJ`a>2+>tNER[LWbSb9=jQ1@:9>B4M(U", &
        ";?(wubXr?A_xPrXBEw=os_VF<l]aSiMX@SY40dI0u`E$Nc3xiacS.dIwY<Zx4;IX@mlR=*Rq?6f8lc<Cr$Xm)(N8;5Yi$/u.RViJOUx,m]b#]hv1$5bsc?", &
        "e78yy@#KMLz?C/c.ks(`zI<X.D^s1%otT<@*3AuuuI^PTmNf6g_vf-P^(q(eK=ZvcP*x0ZOLa$m#[G=,_gS0t9Ys$-GvaEZesrkoa^+xqX^NLveR]F^[(v", &
        "Cc+tZ?NDbagJRhwM2Nv@it5Iah.;eeew7/@uj^RX>d]hM3RuCqN=0Rw?CMX4,oP2K[JFn=Qk?7,Q>x%/eoa#,F:YNNqOKNKS(,9MMwxrCa?,V9@C^iwxBM", &
        "CBTMWjrK%/FX>IRDw?CO]m;[`ew?<_4tr,N%7ZVxrD^:21JSU(^,KA5v@v9^5q]zkb;L>cztUjcC6W;lh-%7rH99J9DgHb--,y[RKgNomwYY=jwbV4BNl%", &
        "t=aKoS<gCE_@Ek:gx^S0t9Ys$-GvaE^lERLZH=bavMZKISAYv_l[xje49<(F6EZ1G;F,1L6J4`D[Ql(m,lt3Q@D,MN>aVX/g3)`(M)SZ>*T2h]EUIRn1q;", &
        "K>@QmqJl:)<%y.hbxRTsAdixHEJ:^lL;g+PlQCNS%.6zkj<(uK,%$rYC*mA$6Xe?qVw:nhvLdxj1)l.n6Y2>j`M#hpj_sPK96$avFMp3W4@mVckFikLMb%", &
        "a3X_Oua-,mV=K89@8A0w]-miU#?tOu093di[tG>,J/G8lB6YAulhH_D0TKo4^Xu-f8>2%m_K:xM1:K5G?H+)M7Ad+p84Cf^8)o:qW@[q.1Rl7_<(KJ*8-h", &
        "(t[Uf5r.)oQ14Fom8z-ff)%:#CRo=9ia#P9uXzyEQ-rg3S7$^B)lsuTYlzEgPO][2u*jGYrLoX)h4JPLtxTycJkJ/,:hjipoV=VraM+T)8vkjmFLMe=T-[", &
        "7mtoJ/rM^_$w8Lk<CGsjrM_K$DY[,oTP??m<kdKM%cQf[=4/UlRw*i-m8CTcZ._drYXZ3oL[rX_=ilK;G7Ur/ahhA6;tGiS7@4qzVrKAz$^63d[`iHmi]b", &
        "Jgx?N15?aQ-N#-YI[A94ctNVi7_TGC86XwG]g+HS9jCZW3@k]SvZzREqq^DK%vpFx5fPq5U7Ndr=1m7w@5h/mVO$>GAPXjWT#7`@Gn?lXOF4u`1VbmBBf*", &
        "jYLBitfW#2$l17X=AV*$/FOk9$Q^WQ4EOfHWDp@+azRD5@wziq*C]rUt)P2_GYM`=]7%<_a.w8y`w6hXwM0i#L(JY^sfTvyPX5d[gLOYql;?5[5ywzk_L=", &
        "Tev3#^mH7tH8[*JM[r/^#sH>RtL6WLL;FHrKPLqr2]`W@kMtDI=_fXYz[Ys9zYLh#;IloR6cDvwH]5qGh#P`HnWK88Zpom*=W<--QWkFzyk<Lb-L$i]jF^", &
        "@aPOWDYlJM3U9Qx(voNhh7Fqq4`Lytd@gw.hF8F7(Z_HG8n?zSKK6U4(hf<47+PvvI@a=S6*=XvVqiDhTPgs%ei.ql):yeXt>0M.99OSp`vnATC8%RC-vs", &
        "E^2SW6mU%A5COlm0R:ol:hwpXWhPQ[3JE*GLdtuLirM^_$b^*%Yr`m+WWw[kg<#G0J$h(4[jesz`<5;maD.QwK2vg4SA+M#,LV_oQjso-=PQ0)aFr/u.c?", &
        "[mi;hYeC7wU.wtD.*0ZCn.RG=>jVUG,e97V5p`m%/mR<%/h/]hm8br<cf(H9827K1@TT,L@XRZD0;Mk$5X#6=[L/`jbgd.r]Z%KJoL;mR;J#wS2uGppFJS", &
        "C2wx;7z@]sXVm^BjeR`X;=/.t]C<YaA06<=/$Tlq`bqm38MjZt,o)i.3#uWZ.OU=ObGyfgt+q*(hgr_Ddt+G.DL%y^fv3f3[rbzOODPAsbZ*14j@QYrQ0j", &
        "8haX]W;lETzsUpU^ca.x2IC/aIy^0a8jrqG%5/K(VVrp0BmsZ3.3ZUhGXIdk]g[v5hue6d%Wax$h*C@uU>KLFkMZq?Auf,yDgayI(r`I;Fbh9/AL(P#)B;", &
        "/m>oqX7UNnAgDZj`S=BG9(fuWYX(ynCFgaLK(xQp]J(3k433ypd7z0:H[OxCEqa3@p6yPP2z0S@[b,DOL6:LiK/F1]/1GPqPs<_mwW)Wt[KFJoo).W-z@z", &
        "O*5vfT$HIN_t;d/3XQ.mqH5<a1duuvsH`>C_`/6@g*c.@p^/.wGC6Inl<nzmIYixT.F^3OaKLEOFU8T`/lOUmJUHip^(2sU*.^O[wrtTK),,Ht)[2ZezJp", &
        "#l.MS^u+WWVrt]zV((,$[Qf[S1u/qX7O^Px_vHnX_*@C?Qx09#Ge)A/u>.3v+:C)qi7Y3%#7P?i>l^<DT]K2lWiE3%-`SUdYvEwE*3ltR$qO6E#c/@jXtQ", &
        "q)Dp+iLMhbtr88NuPW$)TOZfwH+flr]5-qbtPIbo:Jwlms`@rv,O+Z(A1[Tp`xO=,>g%x9MFOY%WK)_tU*h6L>Nj4x7$q1b]Q<TQ5D@[VjU,8MdG6oLtOu", &
        "(@?iE%RmE-hr;D1+fB,-OzUwh:cGX493-Mgz7HTfR;ZUWGy-Dxcd=OR1m=:a+Y.T:SfAJ0ACw?JDY:zHlIrJp7ZrJqC#r8OK%vumd*b:>;PrtX%Nt`am?0", &
        "fS^JcJwC`[-$BI>0(,>bRsT=7iod>s?93)*rHUDhf*^wD1r<`jQ@)f,W0A;@h`UyOKhrChi4vejezlV=+-z(qPkN,9@n9QjezgytgQ$KA>?2;sw^8G?ej%", &
        "r6ajkV5PLG$:z*n)o9A-ek:gkx_q@*;=FuE#CGOV=]^XE?;[9sX_Od%]M:Tyn_hOS<.CRSB_j<R594rqNl(33-6NmQ]7%<hF@kb[j`-;qy8(1G*[rSe2=:", &
        "`;u:*j>7Vr0pJG7EF8d)R6giiS<OhG3MJG8f@<H1pNk;8QQG,SJOt])XQ%F$<gXcSL2`.knlVAPDtk.knexcWF7CtUOYgg6Z[hK,[md8(1K$=ZY,ZpCBUf", &
        "WDcs[%%BljtGQWLLK.]NaW>ddboDdghimAVLK+5W;D=M2#u_q$Yjxa8hMNC1eHRSqkF$sk-UUnMudN`._v$gHM+r11Br^IDiOmW/Tw#,Nl$R#DTv^Z+X:2", &
        "c6-4?`HG$k9fVK6EaHYH,Fjb(GTLI0I^r6@*w2@$/^Ms1=boErnwS)9yrA;BEJL=I>a>RIyZ2h(hN[c*R$1Z,NB[%69$H]_uj5lm^7OVL]SVDu3cdw`4DX", &
        "HVM0Sgm%gO5Mdf_,e3:2kL,`XscE4XbHfY#(Dc6E1W]@ur)*%US;=41,2Lp7PL+RVmj?;,#b1X@`H_f(ht_%A#sh1=7r.J/xLHT^8?Oe7h=.Y,BhecBa1b", &
        "fs<Q<I-f)w26NzWMc:hPPAD_1OAOUW3=2TG=dW3m#[P)A6JR.EZ;byt#0IaS]Rj+K0p:DUB*hwOp5;CTk.3<7RhEhhCQJ/r%U@a7a-7ls?06pwcND>]^Ii", &
        "NB*=AI-_VSt6yCSKhTOP^n[M^Q+B<r$L0PhuX8a%i[:1HT*zCzL3[L@31HGtT4bE^SBP8b^0C]_3[64gV):1M+]4?($)X;T5G0:YFKm09rgL]lZG/AzluU", &
        ".*5QMC%Ud15+WVP?$=nfnC5k$7]o,69W3%V15RS`kM)Npw+DTlTM:Ea,jTHZ*GL./F<5^>?7<pU=CLrtjckgQA(:z7pS@+^N<*cX6,?#S8(X#2lCKZrG9I", &
        "+_I/K<kcp7hVOLuV+:%u@FiU>lWXuzwq*k-*/Nz.,:Pl.e@fK#=HvCR8G>h)mBg#[$d>Q`zkOQP`i#^<ax<D/`%50,)8-ngG9#rXps`x9j]iB>A=`gyP3I", &
        "V*N4DvTwO07.di^*qpBRG>C-,oc1(RO?2N,0UKH0GV:Id<t-fARn#1Pn]pQ#Ey1@-x6zwm^ZOn^*:Hgg<CmbHQRMHFzbDQa#UNthE2HA,Rg.PZa#IpI?x9", &
        "eD=M@?jW)mSEMJ70?QSbJ8n)R;U#5idWK1j208Y9Vee*,Z19pXQSlw=wD,.HP`]4Pjlx4CyM0T`WEl`kLHF(Q8f[0QM^t7(hns(N:DFMjbMWI=_%BTxU0`", &
        "l/vvdY,w)<KSf5K[Q-D,V;M-nQvh5$6@FoS9hDJvfzckVwWUEbbcxRRGFeC%,Dj6A^o6DJp.hfgYs@R70jT)6OxvK0JBa48MI6HA-hrK,zgo6j/ehHLDl*", &
        "MGDgQjal,DInp=e=]t^dAeRISo,G3H:cPEx=pQ[.SmP(Rn0+uRd:H/`j+(>g1nofh8xIT]i$P^FSE?3;/]?N*TK`s67hiV`n@CT:P<a4`RJ=rb47_79+Yj", &
        "Ox/:Mw@O7j0:P13/P=_)QNPJ/E1#M<yu3lAZ1pu:pYDW11I3l>7wWO$*<$Fcl.ZD.>)-Ma:9RJ>4lV/Du,%mm#.,+rzz[ry@,s+tSZw,1gT67sV+j^?AX#", &
        "*=.o*D<rV=Nc9NNdx)ZFcu+(nE85#c27VNAk<MuSIH4BL#u2LPcnF.OUW5=L3V[j%X?mjCp</v#fDD@/KDxzmZVvKBXpPyj=]^s9y:gcwxvwVDjWVH@W(W", &
        "g)n0=$0bONMOAm5H1vAomWb)S_n;u/#v)t9kl8kjbd@6wF*Dc^]O^`ez(d3o5dX+I)/+G2klJgKW^dnR`sO#5BeoNR71HZU0,ixP@ImW@ES<xpE,2N+DXw", &
        "0kva,`r^.?4os$4gBX;%?2s#0zB+/wQmhlxc0ztcqGlG15OW727S#MP1ze/FXN*e]vjI$Ph:/EnhE#gyQI=dD/]S@(Tk1MVua5PB2)qP-AJa_(,.CEg%Cl"]

    character(len=118), parameter :: BLOB_ROWS_4(100) = [character(len=118) :: &
        "t2_6ieCZ?>1do>u,;9yyA*tTG%dKD/aHs>H1mysXY,d7kK[OG>ipKK=iq;n/$:;Ht#>@%ZG8/.VoDXL3cce].Srz7Q+Bps70Ivg4Zc0W0AW;)>w:q]ut<r", &
        "yArnq,-f(Dz9[<wR%TCw,Lc^sXq18*o1.2KS96pP>$Hz3qro(N<c8P(B/cmpnG>h,?g.Ay)9A]b]GKV1?pvExD6W0.TBivZBtYI-=9I?0XY9#VuJwNEl^;", &
        ",s11><X:Wgqk%t/co2ck@4.(Ok8t5GU4@A7lOK.`.Gp*V*Ica.2d]q./XlN3V:sQXULge^;JD>6ZPc00[3;Uvg3p;$gDX2Yl_#`D(H<5MOSU3O=/v,psCm", &
        "7]_I5**2G[ISS^V,k^RPfQ)mCd/-Q]$T,Knf.TtHx<T#rQDC)uS7MKhk).nI-GBsI8hKI@kY78Hb:MOf^fmP3^XY.d_C1X2W;q+Zfs-?jqAUeMk%q(qN.$", &
        "?P.hZs#yT.p8]Dpi+;lG5LPgGMt[Vb0x3Q<R+e0#iy2rOnGvIx@yRQ;eQu4yEdF#-S8yStHQNbLENQdO*3sMQt:VLCd=3jqIFzHdS%(.jp/A]Gh+Gd:Wo4", &
        "%@eC1+=i.agm*JDBAhq:+?j71J)@P1TBF)S:hV8PH_nX=bIH_e?LSwQn`zv]>rC[,gMoHBgSu[T9#MZ-(PaHG7#?bognFE[[@y_6dDi?TgD2+lSihWDEk;", &
        "^lRuQ)d^c2`4p8+u[`DS#Z5%i4V9?d<S#fLBX4.$89$<u:$EB5EO.b,VlpTT6x_C$ZIF/91]9g.7bsN=5j-.FRMcL.HnsqhvU2IUSFKlV]FnXYDIcidVS1", &
        ")VXg*d;%:S?)m^-8D1a$2R+@mdlOmOdobEUQ97oSrumH()%+l[nmMh>w5;mR_Ed9S%^D,B$$M$@%s<z_$TD[%keTDGCsXs)$#Qx*c_L@*_A`>66QP1se/a", &
        "W#;5tc+DrHDfsdm+N^BKTT=?jI5MxB-E#=5-$vcty;nEa/VZaC.%0k*Vwo-Enjp+V*tg:)S=lsIXA4$RM4pwMUp21wGNd6dX9?buTX8wr8Q*V.pGa:3WRt", &
        "3:`T^iR)t]d$Ga0,+@B3`v/Y%Y.HmQH+n^v<DlQf$h<i]Kt;I-)>Urnm`[MI0BNoUQcn`v@P/FqLY;-ebz2Atq=K%,HjPJkA?/7m=96VHir/q]EFMQ-fuK", &
        "21i16sbxWh/UPGI/J)J=fKb.Wf,,41OVdxWdf9z?8tur[;Nf]^P2[,(I*occ/nE4=So*yfVpvjZ-KjY>`Ok-,ao-b+7.iRJM[`N4Hb(=spxZ[7d*%[YS0$", &
        "h%keX1)P2%9kh=#$qQpl?y<PBP<QmbMxEnUIGZhA9,IGZ+whzr2e>19$A7$90@s`t/n)_jk0Lrs6Zj$r,zDVG+xv@f)FTX558%rf-_Fp51[V=Wl7BsS1%[", &
        "f:yKFEm7jFyaYP/DSYRWSE+Ydl.TQOw7d`qqz</n7)*/o.xd#Q8gio)*v[xWL5Ra6;)L2*6XyES@P>PEp8)$Q,2#-#w@Q0Z2k=D@GFY5W2qyLf(q_L5eAC", &
        "BU9G75Ogf%kwM]zbrc,rAOqK$SDWrKiB>vyX)_2`g:LYb];.VdSR[ZgZMzmRh0?wxPTNHpbdCp`9F:5%AFCEA5qTK4`ts9yRo@+XmW4,VPUe*Gk%<CH3oe", &
        "NS/vz`s)n:Z^v>[%U?BIk1d%:z^%se-TZ9sAuU87nv_(8/SoHF`)$ZXNc%talh9$m5x44Q2x532k%=Z_$u[dVbyTJ;Fj8Z4-x;Wa.LWTV_Yrr1_a)f[,@s", &
        "`GNfaD:`#t34c,IfJyYCVRTIPXAiFJkV[YqhjR/p;a:Q#ebeQn[e,wO(98A27_li@-B#d<b6vf_E(gLJmFL-F=1Sst:>=`gAx+9QhpZ?HS)Fnj>0oiORFE", &
        "8j[1Gtm9dN[?NlAY`lsxF+G94=9%5@zme+m-(>:y2MYT-(A/4JhM%bY6AmYO]e$?K+NC3hv7]id1oRMAU1QLeDBJx0rC=MFnJ:zqv8/s$nl64#b:FVEPV5", &
        "g)WzVfaVh(t<U3f>U2/8#fKJ0?r3idkVXbG`Q>)]Htj#/_=Y4:,HSM6*AFP%;uAO@o9ecGh5I2.81DoTSpC=Q.XO7:6S8c.S%-gS/^GI0q)ikSU/6f4rS(", &
        "q:3a^^6Nf3e3wP7+m(UAn_W8Dx:[S28*Q=PebODDw]TY0n:,wh8Ce8ue5g*<#e^9_hquH$jg;PYnb*dUqt5C=@%A-bJAo;YWat^-uKfLC1/*9[TD%LDQ%;", &
        "(C+05r>4n>dAEp?Rf1s_3DzJ)Yb45T[Tkse3BVMn4qC/xB;`G)mAzXi_M/w*h3+cmr1[^l)^IB<fprc]9^?)72HXaKG<GnJM+iKlPGDRmZw`nOH:_=1qaG", &
        "Ikd5aY*bkRO/I7W-J$?e-I@E>b$q(Mlg%dQ1z^LBwIj%,r_GGZ[/66jaGf>TX]B`AXUF<4s3%gLioH$2K:k]`UpyXUQjT48AB22^uis%c#rS(<-?:yb)zL", &
        "/x-r,0#.ZWC9Nk@bTSxL<w#=Tyv*JC/OHxAYsh%H*zl-1W;2.DG4E>h).GHUc/IR$W#%rYa=L)HqKD$Sym5X@X#l$?t0=f8N-[MX_?/*Qr+FC;fV>Uc9/A", &
        ",K[K[^r:H-`.FY-@`gZTSNfM(mg0m:T^W#N_w[B3V`7BP14;/VC%;?;AyoWtCsN;=rF3iOcfsF1X?3:_^BqsSHyG/21iJZH$,k=N_=UlF`iOH-7NaAclt5", &
        "`BZx_o32/KO=fKzEo_%+yJ1U4N)B%);cx<gV#JbEi6:zfotKUdhY6mT^D*>9:h#v+590)i1hbRQ2X1JM9^3s<s@*2Ck6DJpx*KlxoDr_h/v9qd4^jw4+Gz", &
        "Kf/tB88VIaqKj$CEl^6XtjURX:J]OW;0f[>$aRnyTUQug^.%6*f7F7khAhsym)q#;tC8cJ8KYTvc]]ska7$n/Kw>#7mTd-F*<wtL)X0iF,P-#j@g]mYG^N", &
        "A:r1Oin-]V+gncKg9J7T(DCL?M:q`rHdq3i57baVt8,STZJ<qaGAytB+YP(I746qltiOn895nfn*SLZV_leY$klf;zjd?]i]I]B,K_W@aXz)VHDl$`<r@j", &
        "DOw,F<DJK]Ahhyokc^r%v,BA.vL#`%a0DC2u?rgH</)Qw.+Zt1bVGqQcOOhLNPG<t-^``PECnwFfWw(8mNdFjs[,N).-D,aA]7x25UHcNW6l.$4#IN:cgj", &
        "+V,3pDytT?ln=bQ4vOw%wBEBVKfabdy>5VbeZDqT0v/jv=BMcPJ[H#:*Ig.:E+tYXMAnm*vVfAn+R4q#zve$/@ogP9H-P^_$kJ96(/zCFJ$*VthUSL.riw", &
        ":2eCSf*kyE=dEht]MU=jC;]I0AI4fb(wqR#kB*-,eM_`xF*Mvc9rG;1J/Kq`9f+H^C/rX<I?Qij?575-s1li.C-FThP#zk/@*MAlK0Ha<`T8[k(<?Cn#n<", &
        "UAK]uxIDF]:=R/X@UNYf1w#,+Z1hRAcq:/a29l>M8DRf[x0cUhxt9KsJF80XcbV+rW/>iWt=s0$p,0M2G=7(?dpEfoMy%82t=%/Qiail?4#j+Zjp[#d^Yd", &
        "BcDSBtpir/SvU>-A(ymX,sudJ;PzDiPNj6r$*b35KO;w*3$/T]n?l+h:[F#IjmIM0^aA>xw/cwZ2a4]KQp(<61ntmSwa3g$;3Ihwp$*w=4hifS8w62o_Sw", &
        "Y.DEpymeO)qTW(+/$Vy>-$dNfE(KE.mbJ]>WTOX/woeMo#_`,^RtlxK+#%3YRa`lsvRJdM8<`V5<5k8IC@dvB@m.Cx)ePWygC]>hP66)>oO.VkUtv*4<la", &
        "?fXGdK1,j<:X+f^bY3MrAcu>1FtC,;WYs:>$PaY+W?8n3PtCe<;Ez@9>9<c*b1ObbGc4jE@=3eO%/PnTZRv.[C:xgJ/o.kh%m?8e[EwW>XSihREhe@PHi*", &
        "FahaXd-aP27P;>lgB]HQ04bS10l/6j5Lt6?m^MqDt,#tZuB=%Dfwm[Xx)-Zgct.`s++wML)5+<avblBtC4_IygdR>5$%kB-x#zRcOGFzs3,vzYgNOLn9Vo", &
        "WCybwXPOg<sraBE9NY2+^7]+O_aoE)IUyh1BRsTVl;c3g%KZMnokko<vYK9>:UwIhAS4fXUpmR]r8u%p8O_5,yDRO3.LpTnQAV>1c6XM$$`):<A%kse2@C", &
        "VsaV;YeTB[-`eo2LedFqZF/r..ut(<B3Gd_<EM>tgyL3Paz<64;pkk70Y*j9.(9QKDpSv?E,0-.ZE(m^#w[Zz`b>9l3?>b<lM(x)-dF/@8)am3`;s.-<rV", &
        "Jb00$bnd+4A$2cgpk]_27/VXZdl#0UEx6/_K83R^uVO-s>v#oR5MZsC(i4r4GX$z+Z4sje;eor/@R#x.V(:V=GXEZR4SBpJiB5U4L1>mOxsk_fmkqN;rL/", &
        "f)j=/@Z%IcTRKk5BEcfWk*Pa0/4[t9nHo*/.aZmNcle65Qin@w/wsBD9Qh+D#]#w-kH*_Py,D)n25s@Oiy_/4_j9?/(?oTw7Hk%9:htm9BjWq#f5#w7S7Y", &
        "hn<hAKE_0YvCr#NF2#7<h^$T@</IF$8i38wI.Gs*-1HEY])L68VPteu_BLUg.bQ+3`;>Z^A*b/LK)kpsSKk=crvAn>y`fs[8?D*coE<+G^K.;,C5fT(c/m", &
        "yUq)C`6B]z<fy3kgKjd7Hpw6r3md%5Nq,J2dm7c0$]2lzGo]@H#,6[1@z$oIGlIXbolWqH+VO3#>4d%mXlQ0e^-v(34^zW6n%oHQkaq*isZOM2]nQ+O?9R", &
        "AB_OwA79XSZi(Mq5C2gkIhRi:1jP+w(3itgI`?:>lRRXhHNCP>L>Y(QR>P_@-W)mQ^qo-/7kk/5=lg9>-tGL3*UodA`u1R8KfP6CQX;@^0H9tr.[fl-urV", &
        "^?Ch^z^W4Y+W(?O6l#+?%*smulv4OG^LpAYSQQ_=qphmZ15dP?v.<>M@<11BvwSWDgR/q.ND,w?PhnO1UhDQr5@:8m+l0M*9cKa<2Y(uxM<UW=GJTl%25o", &
        "yc-p%bg^r6IA1]g)=mv)$l2SOX<=A%tm7j*nbK%7IMKmU/`Ero7[NE)(88pNeF+yMB)FlFQT52#ANW#npdy0j)YbN5G1eQ0^%91AS)0(0sQFto(EkADk49", &
        "nMN/Pi.C([4o3^=YntpkZVU(OEhTbG.pA%/XWiK#Z6Xf*:?2P=^*phu7unmO8(EWf(rm<zQtfO7c[QO^3/Kb/dX=`Sp-<bnARmo48:yr@_?%TH`W#CWDZt", &
        "s-zj;U(d#rvKQP[-hW1EyD_)X,Zl;t8;J=q(Ge$)kGB<i()*Y.c213gEobV)pPq_Bqw+sB`2D?yK3Qg?5paow3pJ3PZvXH,6a(Q;K:))4H=?H%8T3:MUh0", &
        "fWa82*Lp=U*@QTRuUCEXhq?IwQ(1.8hV#@J9v1<0$9*iAGpm2H@OFzR0Z3/IJEc7eUhXDr0(I2gj40g2dIxpg)57G[J(>hV;3?Pmc9A#V6qz2mLp?r^gXs", &
        "^4XWN:A$DQT$nczM4=:phUbP>U;=+akK[=C[%(x-,Z3Lof<X];n0PC^-?J=_0RjyUrp`6Y)C:.R6RsW1[RJ.8,(^b78)e*DZr,Evb)6ZPc00[3;Uvg3p;$", &
        "gDX2Yl_#`D(H<5D;n<U*>xqCD-jo/%Uti9-Q*3>.`Z?5$@e;XUsgRRNi,2Eem9],0Hq`Q4Qm4dnB<@zA:<MFPAb^u[;C5_ug7ytv2erC9Qv1]wTmmzCm##", &
        ">c_fCHp$ni:%Sxq>-)Y*JECnJ.s/1*mXCwiS+Qfw;EI%7vtmcr/<Fa_>u@70f8(KoaBrl(3eb/-oIUrNYfNkQ0hKG6+>#:y@h*sN%9a>s;eO+?5WQ5wvEe", &
        "Z]_FwG/]4m.qgEI1g1nHd3cZ[V6%UAfYFhq0<I3PZvXH,V]j;SM7/tNDy-XPtMlA?^bfNhQ-D-ChceEvBak1r6_h4[9a>x.=B:#l%^]4_+Na%V37g@#psr", &
        "aEhLI1l[=idfF47Bu-r/.1iFT)m0(M1[XunSQCFG%/7Zweab+f4Be<q%nZ0%/3k9BESey**zm+8mxc5<wk0WpEKikA$.3x7/EV?+j1o,qtQJH?C7l^1PDp", &
        "[?9[uvd[%,(lq,TiYbJ_do#3B/r0:BW(AUTWlsmu[(bW]dH;1)%N#?V2jw6Mme)O_1b2?3vXNv]LI+OC_Bm,ljC$0?N;/ET.7:`j+%GP:L7)7]+N`ruodc", &
        "1E16/i08Xg)tww3MbK;]KsVGjFXI(h[c_S9V=?mwJw*v>mf[IR$kgBjLN8<JIb)=jPn.0X7M.h8slV3GK#y-?d;5d=@DzDaRs]Xx#3*w%0(O0/Hy$9$=_l", &
        "PIj537C@D`I%=aSHcw2wTM=pWJ1vNu-p-l85)K-Df52fTS>EL?`*@#A_d8zd7gdTD`0f7hZ-KjY=PTJ5^^?iIPX:>KO0abCbdEo+M7y`7[4afn7da9/dtB", &
        "i8p0Ez%C<rE2_vRCa0;%<fD?-/m-c3KULuO$[V+wPVa_Z-_qP(t^G6t+37Ot$,ee0tfd*UNmOltD5h?Qf]=a4eV8FPt+_Qd,vV08SC5f^p7;@@RoA)VC>J", &
        "$=]VH0zCq3ObIKA*8#(S#ebD;).m0+9r2RRUy_lWn<@.ciO4soJL2TiPR<q%V/6^S_?=K+EY?I3*YoB+e$Iw-bde9]9r<)Zk8by02y9jQ0DAF=D`BE,WZU", &
        "8).^Ca@4)CHlE#(5idf<%OTbNlh54E^dFF(KPSRt6z*j5Q=[GKKeGKiy6O8*E$ePg$cW_m_PS/OgH/BxGz$w_tk0Cdw3;5_ofS/bCGY=F8+OJY3=OjO-GV", &
        "1N`fnq%/[KrLh+n6>LRGdpg]Q`mw0(=k_C4OAy]@[AC[3^#Cf8@e`gmUMEWXrr<R/lz7z>O:.7/$HV;apKy`>y`m^s;^q4a5/z$gnT;`^bP-6ie^?oO6^F", &
        "^$Gh;ES(mme1rJ50Q(Gu)>d%7*kZ$..(;(U-*S<1CNV]GV$>1V.sCp[s$0ro22#Ka^O(Ak:+Oco[d2NMc0<cgT>i0i5B]o+9$Ko1?m]ZLv(3p+f#_ZcYF-", &
        "k;IDOjd>L0>k$iF,`XSn#mnR`KaRkh#NW+K,;i1NH5`le4`DC;f@Xx376qLhzf43TDRLUd;+y?=ZaSm/:qib<b6k[ih?R(n)=t?N7EKAIfV*Ij5Nb7#w*^", &
        "6qN.W9eBuC$VqrYNHUwo$Y_v*j2b[s;O`xlKUvnx#^EgdJ9jM.9FM6Rwbl-^gu.l[GFkq54bTT^=RHYx-TQt*j-UE60<%hN%.@AOo(^fz@]phEXscJOXyH", &
        "QE9f4iM9uOD$P<_?mn1s;>5e4A<6,SGQ;JnlL[jj%Dmr1Qwjl>t=>FW[#b9]EG<?O^?1qYeX-gr/+?`nx7G6-D[`>[mN7Rb0b4?F:.p/hM`x0hM.@4N`,b", &
        "Nre,?XH<%ZV5S%vI>ChW5[MkgEB^N`ay`/9e%bv$b0`e/TROl$Y_Pt@%)^W;$M`Zf=RTnHb(ncW7Gceg>KCp3]scid;b=(D)@6Pe[:UKdgMBI)8<D(_)D^", &
        "E/nwQaPzX5R5EI`ldd#uefMV/?<h+VWe5WQXAXLaX$zUKs9mt(K[((Z0I]$F**8(2j*z_v,:znNiQ(5UBuiSTj,aaW72Eo_+DTm6,,%JlVY]a199;Xs;`8", &
        "s^r?gw?u.S[,K(>BW,DCAr$V1B+GCOrFKE?GDHA#Pl*QK1_[DvaVYb7Q>=CTMwBU]>I5rcQv-ZKFHO$N_^CMoV1#;IzuwHUd#]GV5+#/Uf-%=:p]HHSXnQ", &
        ":v.lKmRBY3*BZNZ=Xf=`;GIFZ/s5FF_Y0QajI0B__p(j^)XPFeI$LTQ1D03)Zs0k*Qbo/O^B0Iq,3D3[D+;cvF%zbNeVH.5$wU_l]?SKw6;Y(L_+VFou;A", &
        "JZ9eC:_;7@8%[(1a6Pc-_>4P2h]Lw3;fP+;t0-kzE)$f*E51yzPJ#kMY#ahhHpasPq8Z.TPx.+fn:N>T2?Hgwm-%TBk>Dr^]bU/Wv9FPYBTo9N);`UxC,n", &
        "OEAoNw+r50p0R0fYH_KM$Q<I+(z]ZKUM^p/:LS@0sZZu4vNAH9QyaaTIt$bJ9X#=FURjNR(mcFkW5LXU:Dx@HXX;`p,B%b%?FY:AhHwLat^-uFYC]s,N`i", &
        "LE?`8I%;(C*0Q9^4ARp@55Ij(Js8Az8*k<F`w*.KTNn.._K@Z`2XPtN2FL)[y9[6%d)4FCpt4Gx(QCSZ@,mfT:(G].4XWerl0X+*fn[AVGcPV]%wbhYEwY", &
        "@FGm[7uRf=%#1kQlXYZx,K[8./dz+Wa43O1<#=V1?j]COrFKDz,SNk1AFUQK1_[Dt#@JW3CQFo6aT1waDgb:u`RDj.__z:?bj9unt51NH22<DDM4m`TQfK", &
        "H8V_<M^lV>V`^*38-<3r*Zg.EU<G8-cPl^>EAP3Aq2M:b)(jtg(urpth?af]Np,sQ2m7Ag?c`T4#A;xBW9+vULCCLBe^szUNBVs*9so^K<6SzsNh^2jNS,", &
        ";d+F#UR1Roy5#@Vo8+Q%xiXQBgG[b[TBR[l4j5m`TW(kt.W9tcKKn06DB$=_w)D^1nk,orTK#mUv$%$dZbXX_//0qU_a>YoQlmE)Iw4B]M_sgKuYRwFH:n", &
        ")pg,.9dtSbKS::.bA=fp:#h3sI%?I)>O@3ApNqNP9CC:E@_<RgZu;o*A@Vg/1W<RlV_MZa7Kq?Qu/)K0uuR?dPn6L<4GHBANAPV/v(8n4[9a?%+%CW.TeY", &
        ">_Y?Z?NSlt1,l.Oj$ZQ6$8B;)$WM<0eVZwLJt5QVab?;D__8^mutahR$EIJf:(PKk(Gr/Ri8_ftW/i4EWd7Dn0>S%ywNa1V.A?vL%05`7VfGI:$Fuj:pB[", &
        "$peRG*sSd.;td>tm4/>U(E>`FIA8:TeJ.SG9:<JDSE.JQqW9:ns9ZSkXIm1;150Ex?-L(DydoZb[[(3N50?F6]4^_f+#Aj1aKYLzbbL%u=pu(8wtE9hB9*", &
        "CumkQ/9jTHL5A669hgR,(oXh<^].9=JZ+*y36LI]-lNw1C7FGaVOK2pT12V5hH>DAF8Bx;9XlPHaxr$/o6VyJDr_<m:hb1(jdAu/u6ib$lAv(QkUh*EA=s", &
        "wMLnkU=ci*NOkYzAT3l,P%+.3=VE56;o31L7y9xl46/C=II>g6`/jAUtlq7ZyGaslBnKd6AeX.1r@HJbAcTA-A1(<]+U^:Tf$x1b[6-7-+k.o0I3Q@Dm>/", &
        "ZN-1%0-59R/_)=_Kh.8(8YWZ)b5ht`:CC^D]N]-=Wnv8`UTa;.(6X^-oGdb#1?U%XY_**3kY%dNLg^@kZ$eC3l-.y(a<B$n;Sbr$Z.1ufzB<Hep^C%)5ik", &
        "-NOPYQv,04=.`<v9v:_hdGeJ/GGSA1TX*8T@>7jqK>Xe@WX=rvcWC[XY:TQ#5^bn4mZFkhc4#RmHAUyG]+h.WK*nF-t*5V8)WSwW]dWL8kEeHZ65[e7ZoD", &
        "_?h=9,e)e^3C%:m8ka-<xlIe1voz>tFNpad?7b0?m3z%0+Ni=JfAa`70jL*7q+AQu/)K0uuR?hRf)Hs7Kji6qN.WGqEWp#v<NV5hQCaNSKK(teJZO8_%.w", &
        "1a8oN#_Cv.wiMLKui>7(o9N);HJn.NMm>Gw7>,^Q.4KeJ]@5,;]jcz@,`@-VoB%)0NuCV+?#Q_xIXf+PPf#(yoWyDtq_$8]f;AB)c98:;oMMx%$#I8/(De", &
        "J2$C`Ty<Q5@tff;MH)z.f:=8H.a.j4;qG(Tff;K(-v*:RQTs:;(]Lqq*O@(r39;q1)C1*9:bMSlGP)0z.c/YNAqjXgl?kG@J]-j[xg*%<+J%HemCF^kJR#", &
        "jAI9]Hmo;EIm5T/AOQ/YQ3,r.y$Em;-EkCvPLKYE1e:1%fC(V7=uge$#Fr[+K6eF#]obP(E$=b2>ABw?CH[TFV*5*EiEKs-hVRj777VL%)6xq#S^7j(953", &
        "0/A4xaqX0-_iZIMb$xDTHKu%MC^kw5tEN2vF[#6k@>N4(n;*q+:Z-Xpf(++u4W;ocBEPtQ_XfIA.h62aDiK<LUkfCavoQ`h/),=HePeM2Mnj@Ys^-3XkIB", &
        ",EHRv@.77ltw]=Qx6ut8:qdd8g.an69_+5V?[ad=f-k=2dmI)<E>Y*[/)R8YT1]+FHT8PA(%GXcNuDVG3OS88N5t_->$A0*.;OGsYN3==JeI</.9QTckQS", &
        "Gfl<2XeVTeui-fdYPzDMrCZ(^8<T]93(U9,n@v.BNk@mKc)igB1,nEq;+F*FR#KZpv0B[0iYN3IP@;LAOBSUbd/n6.F2Z=KO>p*YU@M.^-ZW/y0<=[UL9/", &
        "J%tzQ@XFQiCWEiEe3-hVRjXwaF/$D)OqNpxFZ]R@0J)eJbcEq(I4M1Db-lWHj.eA<%oCS-=bVyD=)^l1GBQ`,wh-LlhC4TgExN?i8IIXkeD^qlYdCDQB`H", &
        "D(aLPV5#X-PB:k7EHq6?mh..6-MH;#)3wg9euTOfrhEfS>h;3I/uK@P50ao3DNP8_H,uyl)blDhlF2nR/2Seenp(7[,p.*h2:Q^gk0815pv@$>jZjb?icl", &
        "esr(Nd#4+;o*3>OM1s9=%oCvyMsL?+@)lN:_pHn/FKo,`cqW?0odr,RJAi0FVI,JCYo@zQn2O*/=-,ZXerHcDco-rt<I4cHsDkV0Wab6dDi^PhFQ-QF,4^", &
        "y1Ii1mjSW?:*M;O.qI0R89Dw^LucP#lWhAB,/3)e(>FBO-rF6ckWw$Ug7F9za5_<6mv<Ni5Ak`:`ftE8W]1-Q38YN`MiG(;*3(1qV`Gofol.@#pLY6ckWw", &
        "(4CeK9za5g<6ljlMbUoUm+Wz?I3we.ZOk,43HW0hb)wejh.G`CQqYFI$B]*VAB>0D2ql6HvQD`gW@_>GKZKfq;,2T5v.;Rktes+;M>Hah91Y*-;cJgy)EJ", &
        "%zbyrhqZSsZo8-<3r+Wa43db_i(5$)#ic#ihrfYjdl^$%]0+Y^7;d($O=I>2jX)9y7$_`yX_/%.siZt`.S>Ub-cAGc7A]?SX50;<mahKbE_q7C4xMVSKj$", &
        "eTpv1qeu69qk8x:E#<r1y%$d.2jChP6(w^N4hEP:$lD^>mLEF%Z+@XLDoO]@mVb*pVaLL6qN?3:^_k`$t[SY?PQ.IIyRDPJN>)(DE9SakVyGZld=l(tWj2", &
        "Wrw$<=<Ms^/^=E1-kYzlc3gm:*2Avw`%m4>f$o-A-NyS:tOEvOOHe=r$-L9Nz1kRGw6NAqt(O@j;6$+WqBb0<.,_A*#MLym/MI,KdhMOa0D`%nk9x#+OVm", &
        "_Ez[MK`*[W8w;(u9E2DYV4iqe*`^N_]o/DVHrB^)Oua$CTUCium9plFtq-J>IuTi-IjX=]pXjQ7OfU<S.TsJWvP5d615CO8(M)s_IiF=16`t>wClq<q2:u", &
        "4t/mt9;[JIqqU<]izYf17f-7jLEAVP4i)7d*n@Nt$?JN0A[CVIBY^`KJ>*1juXV_V2Ey2LRs[.d$]3iS4_^vP=U_(64:K5c_>$f73#:sReQV8s^wyBuZ9@", &
        "xh*D*N#bs>mnVMxxL6VO84+Iks$a<UCH(x*[r0-tq5^;Kp8:K3eb^aIM7s$L+xMsnbe;ePbve#-S2kP4Jk@O,@zc+3@A_z?a.V5FO99.,A/9AeTW4?MMN<", &
        ",(l;_kv3nX<`1]<O;`LE@)i3fx^Y/ENfW.4`=:?-F3L=)*<8r%%bt6O2-8Bd8aU@n9?gKs;@c.uc(qOw*jF<`IbYx1SlSfJWOXM*I@yE=G[)<=%nt$NANK", &
        "Xv0D1SK`?oO@x)po?6d0nZSv1)D<404]63sXX7Zm9=lYO>nmHb[4IVHyWldYS:7Z/6mls8o-A;wqS%kzRRVk-GZYGOyoywS^9c#Cv>3`B9XQ(/.GUet$?l", &
        "S#ed1:>ow?vu1$](o`$s5]mmSs4^GY<:H<nR`lNUmoOcW$J.Qx%b$j03yJ,J`=,BHPL:(zYG39WSB:0d-pp4.mp04Z$=y/08Tr.mIkiJi;[#-uEf;%KLhA"]

    character(len=118), parameter :: BLOB_ROWS_5(100) = [character(len=118) :: &
        "GHnT-s</kj:1mp=ObPn4J%I1B@rnf?e=IGiWG1a=oS@Y[i2.Xxm.]UM82gEApMe[:F+:wUo-cm,hojvB4TFB0eqXe`(TLN9TK#)pQ$u3fo3pkfscUnyjFX", &
        "I(h[crm.,j6%Vw-iLPv_.HJzb27<0fHL5f?3hIYe%0B=N>v%e;oPd?ySGK]4[Olzr+1hnyobY(wM;$[n``Fl8L14MVF/Jhq[:tWtw<iW=#W`(;%=m27bnM", &
        "7R2QEEzk;6=h:1EB8RjJ+5bY$H*7,1D8?2])fZPYMhq10bHun?IaxonG,-5IA^JZn@Cs0u[:qNQ$-;3KOqwbiuZ/,5P*c+w>c%N[hU?40,8DVOe+=ZSLQQ", &
        "FK%9SN6f;@V-tfVIpxkq%R`@dgjS1A/=zno:.L8#)Rtx@%[Kx$$tOM>.8DUSaP2?_2c1E167?$/^w^hg907b7k6eccH#/i$4MbnPCT,a[6)Z_PaI<0EGJ#", &
        "Uy7go[>RTSmR=NcCd=S::d1,Mu9*WT=Z9:oe58I[l#`A-74;m_0l3s:-RggMOTZgT8YVW/yTSnIo`D:PpJ`,:p?W7(gqMDg`G8;M?1>@_T9(h^[u+M#WDb", &
        "H#Ym?=7?R>?Dloh<fz93hl]<VN>gJeVZcYnPA]`F%NmJymLA^GtX[RS=pBxNk;GToVxHba>0CBV-ymi44G[/2,ouVD%Ys]gm/k,[2#(mBgn=W6<u@jDW2T", &
        "YPWfSmeKM;y)st%5k/LY_eEAn)W7#^<?4g2X51T5X9ptT+PSp_egI(q5ECUCk@8xFV7E>P9w#kd-N:k<k;%d1nX%.^Et0L1lkfnbm.6Hgj1#CR_;[yTkDv", &
        "u7x^k5zZgqcRHb)?85^1[YFu*p1OVOdTtL@eAZ@@zO4D:W#J3ujbknCb9*w:YL_2%lIFu4[mU9ZYn(yV*>C*N<w)1L=g)+55O2jJ=,ynY43Vz,M[@WH30J", &
        "XR)>xOElDo%<5:C>s8bC`R]zh3V8(y8%vhd8Y6ckB-e]Ce[.6o;-yX#`#NRj;*5eb#1qilFWv=w_9Z%]mV_+OLZ_=6b+Iw8C,J`=,B-50_-5]9ZXPuw7OG", &
        "jbG7ysp2SGpe$I?uKr3B%B^Ib)hGsiZMtN4u*@k##*Wmd1<2$iHPd<Q1frnU@-mTihiawFQlDKfYx4/ap+@W@90(#xk3r+cW>w:)Ls,jFP:8_5XV0^,?7y", &
        ".fXzLoc^(1c7>w2,ax4`po7YqfT(yvEC5QSNbTr?X8Z(lWNd-M?phL5Z[u#xe7jGPXh(.PKiW>[s+v$E(y,>[4e((G[5Mr40e)b3NfpJMO>5G?9u29S)m_", &
        "jiLS3?<<3Sb#YY.3n4Wr+plES#>G2m*/.(uH]?]8i7cYp,I7Cx#`P9`1oD$MO,R^AsU9I33TPz,`r35$k7-_2DCXXKg@Yi5o1Q(Y8hsVpi21CU.P?2xw->", &
        "sB:ZdCQ*?1JV[:P2P*pPxgZhE=JIH<5h_*Z=]l,6%kQ`+/n=^b<?i(O3F`dS*8WP`ZMN1MeUAQ6oc;m?NwDKn+ztb0r2;>W;m2LfVCwFQo-Iq6aCAK7(D[", &
        "#um3]MJuBn2.Ac]?X=$*SM#:6xn$(a<5,rVi8/vk1<^Btn79jG=#DcZs*J;k(Zu9d?>V[L4:?AnvI3bry7-STC,9GXJZ%k01>fP7-*K;yG*2,Xl/O/6;P#", &
        "RIp#8(#)-i;Z27B>Co?2_I0fOFm`eY8E<=JQ<kr8*c8O3b-sMs0_].=9/NfcKnj*h@Gc,kY`z#rxpWhukyH(I[Z<S(3M0`ITs,P47/xQh(s]Yiqw^0pR$%", &
        "HQZleBSn$4+8J_O,Ip)(5.Ya]Fzj?FVW%W7UECA#gm6>r@uSE/l[3_<dHC5]17a$r;I@*crQr_dK[76M*%br@$TH3s<:S5O0^hgyHb+1l=@yoO.@D$5Z1:", &
        ".;NnusGH(LdEYl9*LfY;f]>.^IEV,MRyR+kgz1ALYi9mt>BRqLV:pCOR%:_G*/t1^$f-@UaTW4?>xK^00;;iJSkP^1`[oFN5pd`.T1sYXTp45c3Lez,TbU", &
        "gi/f-q]X;#i1aR5si?A$jM6i/ImgEw4.j,Q7%md_ydP`eNi62XcKfk-eDCH3wPh;grL[^_W8Dx:[S24sQ_vtaa^$w,@`0wrleGvF$(M;r$[EYL$sb=Z;TN", &
        "KEwe]=:H+tfqq%amLh(I;O^O4,Y3X$^.)v)EQ0e*NnimoPO@j3T)S3g6e4rGIHVa*2p%[#b7Hs_[Sn<fgA;Q/0*PKQcS=`([psH@uZ(.Q(JC_Ln>j9MO@^", &
        ".`b7+y:(K0kj+X.7*>NAG=mnBL+^Hp^u`3Mk6bQq8IH8qcP:X@83fH;8mkmpTmF4/5DlM%UDmv)g+PO1+Vt#?cH-/>ulG#=avP]Z.Pn;SX8@8,<dd74?@?", &
        "Ht`_#e@*=Y<B2gCMV++8*n*yVb%0P<YwX[R$U^2WV>,#qS@uA8DS[sJ6gWTdHpX(sCl9[0WAK/kGiQrl2wf_n,BuZT(1@UJVBNA_7<8cY@J7wfZ37f9SNs", &
        "DApWKfQ?t:tehW4KJ/:TxD:/fG?T^xGDYDfEF:>*HcCE#7T1.FoN<I3PIWE?yNk)1X9fVZ$1lke)qornLcW9K/((x+Qr.+dC%#qu:VMo_lBD<%^>eF?Wi^", &
        "5,ouV,Z]1.GP<;EQHGzhO/)Z:PU/hst:Qb.O%K::wk+;]6O)-7LD)9w1-j.MUP>z;^c%9D+M$+G2Mh](%Lf8D(tFuqxS8w+k_Z4*4h?-/#TaOUk+wo[hTV", &
        "IL=brf^qjDaPmSF[6vc3n>P^I9ZbC*E[BWo%jmVPxDwO./GWiQD.3?OFWT4z58=EM,:il-*$N#Gp=V0Gu^X<_Sdf9B(oE.=w7asxdH+o.LeWGZ:%)XNnR/", &
        "Bl4_>pi@a+4(phIH^TGhKUtX]iRK$%R6XKmk*N#PfbEj2b]$;O``ncdRjI8kL]0B7POoX`91(7$Y;hd)DQi8;<41h2;k(t0SR`>@#fI.[a$[/rGAiNp=Hq", &
        "0x:-lkJJgrnPt@Yc>W99s2C^FPLOV>7GIFNKsE*=_I%W_q`;_)nHHiuK)1ye.4%dV-=N6hpUt.U2fj6d*exc51tH_.em@M,iE-LW$)qXE:]ABI0(_`wB74", &
        "Vccy=hC`kk-DQ4nhzBgoB?hbGcpOWA2F,ZVRrDI<7oqMQNL<sKGF<H.4aFXY@hHwsHvowwAqI?9QgA]>#DhxgxVej-QqIOSy,FqH`Z,,OJeVAwv.`bmeDP", &
        "Hya6adN3^QTL8Q)PRoDPL06zEA.WKHSM[9`=nwna<a@N3B5l6BKIG-Sa<mtcup::]Cic1P4XCy(hw#Aeza^%JOM;.+qYCJ-FUPpQblH[+EhZBWlhz3N(4/", &
        "cq;-A_f[14ekf?gbnq%/[L8Zy=u0hNhWbaCCcT;redIQfS:r<por--(T0_#o9]ZVJiliI;h]jjTvO7PTE]NL.h%6p$58Y.6=I#VM8,X<>-#?U5+TWPystY", &
        "tReHCv+B>m#;*#:wwGOOzLi%H>2tZ_)_snBanqLl*5>pIi4+XItc9Y.6:zKC`O$FZB#k2R?ktXpY=%/gm:LZD#q((#QP`T,X5Y/`L0MH,RyE51Ko)1Ok3h", &
        "esaI.6N@6INbNw3^YIAR#2gS_?JImz.?FS_*+yELwzVm(e_K5/DN[jpc_7mq0(zHq0`uZN*mo%3YiZua#,g(+=M/#;?jYgFLlPp:2Q=3z0]g`FL_Q;LmL`", &
        "5n,BD,F)BFTTh-@J*%hy^Sw1-1y)J#`HMTxFi8h$pz?+X+^TFvjH(s[W2;(%0H.`2n@VxKNcm(oJq%j>Smbc2UdJw,%^D>gX?,3Aj22HqVa0(Qpa:X]Zph", &
        "CmI/0O-zZ#pU,@6,;<bb*c_ZYRwo:kNkB>uy9K1t.YO<-uZ/i<nRHbKvbDDuIxnVEJz=2#JYddFIp0THZWFEwUt)(.jkUBmxTUH5$#`Q%*r)3QdYol578L", &
        "@ppY/#L+XuaVfkrt,866p71,US``>ba6,9cNWx5Z@S)KN0,+tjeN<0@nrH^J0m(0[Gp_KwXwt_<M.C7W:F.?hd_Tng/1gy8,*_1?f[b$S.PLgGOV]x=E2W", &
        "<h-[IS,=A@Rxwey40nj)N:H+<Zea<R(rp/a<(F8u3B_hAeUmi_d/*dupJLTUsSKmzZdjcc%:*#srsx4Qv>q%(MVSNQ<955I_z,:1wq+e7T3/W:iL5%3SZD", &
        "jmkOy1vML1;PKIT-@%c1:V#:z1jdu3AzuQ.tN;K^d7f=gZ96ZoZ*;WKwe-Y0ZU,_>0W>7wT(3Q%)$l?LS=CV1ffC4DrA0g+I/,2hAD9SgU+wY;H/:q>+jY", &
        "r6[c`]+)$l?<S=CV1ffCe4Juq>O9;m+?S@uW1UT<eihoY+f(SGJ`Z2^S1BBef4XP1@1uWnZ6A,k.QEgpr^+J$T,@Y:f3H`c/n3+O-bUl,t(Ldt?%X1PY/C", &
        "o)hcb(?PID]z:$=$lP`P^d?]H.AOXK.;^N4f1rMNThRg.BwU<T1j;;tmk`)k%/:$UbHQ(,/i/)7)Eb_0LC^siFqg_XLg$H6J$?<DYB9MHV-dCVn*R$__=Q", &
        "ge9E,$=.RW$@/]3hguz,#ceA8QvPEb#+#dhroFZD9px*(42_RSZ;jPL/R?yi]MAzEV%),dO1`O;AKJvSmn-d?*ja`aP=X*u_XYEfj9wlWoLhGfov`*yWi*", &
        "LcTnirj9qrDPC:QBmaus6?2v_t%;s()J7FDtQHdxEQrq5T`)MfB:o+JgZ%qr(VAl>v6J)nU#/*^Y1o*^Y`N0A:PB;^RGa;^SImnirj8DJ8P[CLMp:D(oI@", &
        "M9([nT:kSt4XCV/%lnS:%lnkk.An3S%;Tz$cMaU;ODz#Hhq4k/=q)y;@]+Qo*[(Xu)I#g0M8E^/.#hp?H.Hk`qVq8%btbFWC+w<qY%058g#0QH3<msCpuR", &
        "cS[asGjh<=1C@$^IXB@F7Yg6J;Q82_2p<1@%sBX*<+t80E)F+cVpkxux$fKxn1/GgR5i2zMM+twSf4tXf%(1cO?(y>0iB]?lBVM$<;VRrW`),k)lO86pzL", &
        "$Apg1@7T-mLuq=MHM$Li6w_>)8?-D:x2F2fb1Neq)NLRC>^_nGi=ew.$v6C3kprcOsc#e[FY03=.tWFM@[vLw:t*mXNOl3:nC_XRoYmt;%GXO6EB`XO%4Q", &
        "%fp=%^pph[IKi/zHd#IWY3g)i1qleSLEZP%I0y`-(Oi>rke$@Bk#DW7y+u:Vyhtea/.1.^3YIo1Ao+bj0/*ME_eJWC):>etm;$]vLpGwrd)1$tP>U*ASHD", &
        "D=JGBbIxTCo-VK/2k53[RTE(0D#IEicaX+MYpn3q#y^I//6IE,TKZrDE;*6$TaU>NfK)AhRUs9xlL0%lG044[mU9ZVIhZV*>C*N<w)1L=hW*o-0f-wb$4w", &
        "g[6k.CKu<]CqB[#87Ekd-W0Zj>0%4H%`4thsHb/k%E7OgQ+ea)>//SC14,#aeYOW,DVKYdv`ph>:7wQxe%kN(sQBzQ1,VGL4k9[,%O*pm*D7%CQ,le9wNx", &
        "mva*^<QeyDo?qGjDs/AhIbw4N+g2L6P4%ltn+9o1*vCF49%7iD?eb;b4;neJ+ZAky,[D;F^UoW?7(Rc?Jlr(jnT33Ntw:p[e+/nExrs:9Zs-cN375/qGkf", &
        "FTe>_swcw^:p>;x1*QY,?#SyNorkAmXBBR+hJX>k4Ija^[11EMRsD^9;wMgcz87l6BBp?tQl852Gb*ra;i=pb7JjbneIyWO;Gzzok:wYXjVek*D1yc;W$a", &
        "C>hA?a1StjZw+U[Tw_ZL%77XgIa/^ZBj9Y;Z2Q1kp?,2:(YP[lQnf2o7*<w5YUK_l]OPIcImt_Vl*NXgNkac/V49xHvw+p<[MRq`eLa`@XlB:bo?E,f@[<", &
        "=hgDaJv#)>D*lQ.H(NDk`H61hC9(V,H2nY2%SH@d=%)5-kt*OIQ*3GSD/<IEAu1DJ8.IjgZmh-AZfu2[0@c:#N_G]FS/154QLl.O%%AM.1Bo/MS$/Obx?G", &
        "M974-,[AiVPI)[MbB]lW)Eejv(L/fZWAhIJvG+?GTN@3k<`y>dY7zk9i;>729V<g,<0vn80qhq_RMjAKGWj42[YpO0>_kTgAe7@URKrm;T*OY@uc1P85*j", &
        "#PQ5Vt<<I=G(SmUQzY1]oe:VW?6o?)9$:?L(D;^iC84a^$:kxx-r[7]DFaW_r]Q.)/rhxQfS3_1Sf%kO/sFt$LRHyTD;NVTniDgUG%,qC_(.]8.NSwDg;S", &
        "9XeFC.MMFAqKjiG)>)(1:i?x-CJ=/Q80gUTml.9*Nu;<*xFNeSSTpD$A/w6B=Z2$7O@54*jX^O/c(8O<Me$5CW3JPF]^J,:_tPE>gbGi)]nVR5GdYuLEJ_", &
        ",7U(/JXXT/dV$>`9XzIQ7)`>+FhQfYdi4M7<*Gm7bmR$b$7_OTKEkLSEs>UF:o5OyC<F#o@9l;x3nr(<:<m>[lMfaoEOE?kPG92)RZq53.jc:nB49;fQSz", &
        "[$zG24690b[>-r`%^_K4B2wSm_ix>/0_;0GfV#?T$?N8FXxrf:>svL6-IF7<)kuZ#2[+-c/9inQBI^D7b7WEg1(l=(v6*VphEn-@c9IhnH1%fDzxaM_8y#", &
        "X4AOatSoj0>hAd$[IRZ=Pc;2BkZvz473K-G7T@.>*u4R;ZYYNL:kNxi8W8DU+8-=vXkfSX<c97Y3HA]KYe?_0(=K.GVqdQl*C^zB>FGb2[YFA4AU+.i*Sv", &
        "fE7siRm%_tumpg9Bhj%fB,EqDVqiTKCy:h/WF8>p@0X@arDF/BXu0B@$2mfJl0(m9f$BIzY%u^nM:rM]LNas7FXZnX;0$V6Tf(yQ7x#W:-<.nu1^cPfKzA", &
        "gHAqDLh=1/@@kj-<Gow7ZBPeS6yxz9@=]O0;CED?:sWJ_]dVH8,i6@GUT6%?U=Oz*2y4/cvuCg>4W[ohWqVd@^gkFEE2MPNatXsfY?Xf@`D^)(y29)q8Ba", &
        "2gV8y@#vU;zP2UR$g;(-=af/z<Dn%xy>m4fpuw._-qLTB0/e6453q4p3OB342%,ip.MeJ68-G1XC[*kQGE<0U7;?-pNSn7<*,>8HU4T7XO@@s_)hJadI75", &
        ";*6.Xrj[rlid)EVBwNZZ]gH$cr$G+ez6X(IAp6q8#2i1x-Xx;PgsmRerq]Usn*f/>uG`e_Ur*6Z2G%B1QPmcnSo<C.F=KCt,HS%aNB`>c7*Heo9gH5-V=o", &
        "-@S#oil[N(DZE^o)2_gz(o>#97QNGe@Y6B%;6@2K0ilJ3/$%,%SWr]?dTg>7=Z-d;*<;eCT[lq]IXxd)dWVC,[(8bcaH>]t?6X)E>$MLC.0,:M;Oa:+$)a", &
        "LOHmv]cCu?rgviKWI`WFE6<P+7s)%f-qf[dN]foTm$D[,3R1oY-=T7Y8>E]=^X4loM-j[dR*ZFhy0`]N9dI;+V,blJs2YwJ:oWM)P:`n9uw*dhLZIr9>h?", &
        "*5G>f(pESov9N-)BzWA<DYHri8BuR0Gm.Z*m`Wv%DjkMslyJ/NHN#F/>kq,JS7P*-G)=5oODo8cpeREedM6CQ+6WBX@9uBI4ts3>rRQa/8A;,iOB$Xbjd]", &
        "9w1zP?@ye,IMh_Zbm=9PAv,hy9o9k3LL)Q:Z5M8*wgX=Q[GzeufFz[l>wJ`9;J)UJF%+mzw8x-K;ciI]9ZtFmp#2V3u#42,ICQ1P2L>X@ZA6Se*;CX[r<i", &
        "QmX_pS/JKXqnES$>zCFabJw]lizI7_P4vK)TIP4]7k(mJ-Z/mC]kw%iC7,6W2Zv<px<F6a<(/=iFu62H1C:FR7CI6B1jtr6fh@B*Jd3:.YmA)%hdaXaA?,", &
        "fIIx?B?e)*c[B*ek:@3Z*M0aJ:*uCvd%p)SNW(%?5cQd-H:z:/<=OLr*2y]jE6o4:sn`Ofa?>y*TDt7A+5Y=c2R>j`X-.@XmPjzO7zNpe:KbscR^+_]]T)", &
        "xdP@5q25MJUc`t%VEYV8-%%dY%e?Cvm2;nLCy:rTWC#bO0$qyQDfkk)j1o(k$s=[fM$dMWLg;U7jxP>_50gqgheB;sHJE6;oXD1Mkk[6JB99g^p3NYl.W^", &
        "-Zv+PZNX0mUX(Whnio7u@$HADTfgIH19Ev_qz.qH=-J1>OQId)Q:q`uhOH3f1DfhXYdHi#zUhTCSVP/T<H/%-,xp6p5Y/eKN<jzlf1[9O:XQJE69>Z]r>i", &
        "6@_L%f)P2U$Sbq>-($=`;:M?QJI?6S0>[aQ+LVzj>Ix3+;rrdr6:^n`+o$`<gti:NcMOuMw61=*6hS/s2D-4i,URI]g1Kl4;^f%v.*a%3V(^/G#TGRe%BF", &
        "`8hPCE0;%lNXpa9xXMu0rv8mNXHf9cJJ`R$iHroH6k+E)0N,b?HpEL(5w6(C[cvupQ9A`73q$HdLOglc`kw.e616hulCa#8^Rj]/l-]PHMh5NaSY8B6-h6", &
        "RoiHa-l<W$nABUaNho_kLy#.l%:X1=/q9VykDw;u8dR8jq1[4hM#f[`:,H_gYfD7*B<JKuO.hISdaF0SDierFa).^q-a^p_HDSY:G48;Rb;$`eCb4`yOi`", &
        "Q^<nWQ10^ZwH#zmp@d5`rB^tngoWniX?>.gt/`4_kbj0uoL<N8=4j4Jx8oJD*%S=Z?Wc2t9Kn(_BOFTW)3Ki`@.<T-AuqV8rz#RV;yTSZi=9YE<a21%Hho", &
        ":_+ZHyx+^(D%7P[2w[siHOSsW<h>h0.DyKQ)Q*Y(]*Al3COBt5kF;RcF?S`9Y:Ydo*%ZF9yc>Q<e<L[Ybdjjqp..C5xvdyJlK91ewrpfPze$n*pp_6d^23", &
        "h>H9u^<2[,c4T2ko(p62xLL:QkdLn0Mf^:hcSR2fuX)rS.:P.[G%+$u;fui8Db0D@.C#D>S9]KKQx<[1#x<[1#x<[1#x<[1#x<[1#x:wHZ/g4SqucQyrx<", &
        "[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[0x$SLUS4oKy+d*wc[w*.xwN0RMOx<[0qx<[1#x<[1#x<[)@I;_C<6*L?5", &
        "4Mm%MZy4tD)Dd>sx<Y5Wk3JINWhEenx<[0x8Xioj<N-)Ds6NIq$N<b8<Lmw3W_b5o>xYyLBaEKqBcg:St/_jDIheG,<*RTABxJP:f$/5FDCQA-YIH>O=0>", &
        "C9$gmL-L/1(^#+dB(f>5=jsAw3eF1m6x%/?>T4uw[G-ESe608y%uE;Bgc,uoakjK<YQ.HuKT:.`hAQlJy^@b`A.+RZvtL)]?@T*`bt-F/#@M1YSCd%;*EO", &
        "Jy-8gfIexp+<YHEW$]apl@(Wd*_G/dCjUApYP]-EI4M$$CJ@9oR(AU/Up]l_5b8h_GXi;kH53e5qmrpPbh?j?W>J5J=K87Q10uI)hZU<iZ+T^$:#KpC35-", &
        "OH-J6dOs.$a@$^^YAl<oSu)H_0Lu*,=6B*EI$Cl8GeMo+*rc0wsRBSIN+G)wQw/n6yQw.1*q5XS82<vI6gc_s$6cRf>fj;-(j3NP.K.Xi<9v]B<AIP74YG", &
        ";ykKlEi.l1ZPYs@--YONf7OXfQ.,c28wPi;h*[q3?`_@a4Cz)@kGPdzf)D_a/t3VY?.wb_qpDW)R/OsIbrxEc<bHkj>mPUBMKoZSES2/^e-+<Ig$_-Qc*t", &
        "OsLEg0PLSXm$OSY/GdunU9xH>k=7]t=5q]7IxG-pLE*d=N`e#QCr5mrVjw5`O`.*^#^A9`CJUIY@$R-L*^+olt(-sD)fk^97/Xh7l`K,#eL^+1RFL)mGRb", &
        "0wb`8mH,9_Ul^Zd_#YpTS_NGL(YViJj@)hXoAefbp4E#*mM)Rx)d]$+G$lTns=K=7:*jn]tKV=?wtU2D,BjXNvf52ZnR#R^ed0.=MNv7b(U)zBX)g<S%HC", &
        "Eb@:C*y3[:[#Jj<6+D/hy34-ieXm4klWLID[v<Qpho%XJsH8Z1ZNf::z4/V_zq2mr5k4/El`$LURtWmloU$ZbW<czeyCym)75B@Wb(6<eU.eW>7;.q,7(T", &
        "A;[e:xU[qBGW=M_krO<]MRes3WC<J/SF+fetY(*wlGr$M9c@$<+;g76vrf[:P6ATd^D6HD4SgAbpGts1HAyAejk`JC@0Ckp3:[a0FX2`eG?:CAnVmVp6))", &
        "P-WG_F4jj_6u#=;#%vTI-Rad@xif;]YdTR%LKKqf0=0r9-#r3H/Ddn:q6fFbNJATpXgMut0.@_HqG6TwbLrZ6HedD-EmqM`[>X/*)rNu,DfFd?WA/D^I=*", &
        "f>%wN2o1^Q?]E)SaZGJLrY%sew#QKRNh].:vSWXR=Ip#BkljiPu0RLwSRSC24tJ1n4Sp=CKk>-7azln0XnK<r/IE7S6?6gXbr>U/X>6GFP<(G5G:Zopj4q", &
        "5,x4>#ail?be8w^3/Q@#oM:kTK-73glHFK$7s7[.q$PK)cm5JdknS#g<I3o#H[+Q+I8T7=b)eJnb8#xalK2??(U0InYo(3v[Xvs3kWrIQ1VwecU8SI@M,2", &
        "?`A;J/y3^x9`T*%@[5w+R^fjQNK$iK1xOHl+KmX82ovg*=8dnblML3j;z-^Rqx+H)k<x]_b>R0kCD_F51G5J/M)S)x0xrd>z#J]nzcmf<VoNo0yVbN;R2f", &
        "[XckWq#(KOeJ#`C0=)$yqfJe0ZS@RH00Xz_;0]@KD8.wkWhh$PZkcAr/NinNUq:(_*Gxm31@;a79MPFP?Q<;7y)._Vg*8C2c0%uaa75[6C1GMZ7%ec+*IT", &
        "M)I(EVB,)-Iv>s2]RuU5<=R$uCSbHGNOv,Sy/%PnOwbjW#,[4c6FwbM(U?tG7:/R?AM^H3?O09fP*V2zdNg%-7ZP@#x4z:rYcs;(?#o_-:Y%nMZuEr/s3+", &
        "LUV].w0ft(GO+#SJzjk1qk^X#9jZhZ1a60RoN$^+87R,#*IsQM8u#e#N[MY*#CUPn:T@1/#T;D30#CN[:V4yiVWSsitHz?4jdFI[Uv@(YeQg(C(YH$7.-?", &
        "n89<*lh:5L8r$EI<pkRP=0A.:E^%g$dJ(pZsB>]bb65e(-<;,zMC>[8Tb(.Ggok-6UjYL_0Xm(=pI*b6cuUM#)]ZxoaA$uV>k7v?J(r=o?a+gOa%=vmpQW", &
        "6g5TNfIQ?c<dJ7QZz>I3MlB>:kLr.ItE3_%5S:%f]F3/hBv#>I<$@Qw*U6`)e/X0)si2@+u8hF6/(*X9]O7YiJ[w*a41Wx;o=_Jn*vWSR#y#(rRD921M.%", &
        "7n1`sX3jKp-oQ=g2*0;RsCTLdhh,qzC#OxY(rgALo*>Ai5nTW9wCP^g#OKB.DW8OQs$/fvb8srb0@3;9A4aTv6hosH*J1Ki6eA,q:0:4f[tAByI(OD01Vm", &
        "im?ijz-l3r)sa]IoalMGGwCIou%;rnh%rcY=beT;,pR,8[e@4I:[XSM3HtpRbs4#@4(f^4i0P7JIw_S>^B1=oN%.=pM.4p*947=x$M((9R`U%6YzLHh8kA", &
        "Bl-fwk+%DDV`pa>CB21Pgj]p>?Osz.Ic^iA%rvGrYUQi;,y+X@O/7FWPjOP0tJ`kPb<*d1f@n0KS]o]-]jU;wfv@U]8qjPN+KE`)Ak#wvB#K+t%Nt%_oeS", &
        "hE4_,I2E1SgxDe3`d^hkQDI1`IN/5w`o-VmZAlGfiNEH*-`AXQ>=)$V02^#zQ@9kb+aQ-N5cOJ*pz,e`DUDPn`+F0pc37i.YCr`4l1.A62((9]CJ$)kZ(3", &
        "J/qhm,Dag:.=h`_c%v)7bN88ZhA:-J58^hhzLp_2=>Q;oZ7g@p*F*d2Y138W$3-+a*</va4Q*)$Ky+l>ct`yUIDNF>Mg<ge/UuQe+KW?uvif;cr4TSo[lK", &
        "y5yq+AsF+/45KK.x_4eft$[C_%B)_8ydLx9c=L^d@SQos8dHwCV,.b7r-)-F3<=-y?h^EV=YA+3idwUt2d+oKvU>ILc4;^I3)jA]E3>.GPNg;+t.b@^0)X", &
        "_l5/_v+h_X1zg6y2;CIU$k96=aJB$$K$c)$jdv]g%d8U8JRn)jDRx%KFuYbOq/Qg=-RbU(Lu5$7VI<)nJ_TmoOJN:k-YC>9B(vk]$KA=A1]4,:/m0XcLXB"]

    character(len=118), parameter :: BLOB_ROWS_6(100) = [character(len=118) :: &
        "Zjg*X%#ATl`v+vR:swZ6db5<kOku>HhItxvP*%IT$9JESUgepT4t/s($Y(#%mRqOW93JPC^5d]Bh.^Y+i/aGWv_yi2ECupwdanEfsLod5$L05.*7,:=(n`", &
        "zPK5zhmZjl84M5C,JBTj`gmZa7F+dNGpH_ltEe_PZ0Pei//pac?ZMQ%Z#2GqAv#?r59Dn96ZrFS9^oUTw_6%a/3lS#%mA@@iTD.hxArY(YU$E[gVi0_kft", &
        "q4(t3X@n;iK82Woi_EHun1tfS%.eu^vKR2q*ns8DUHf>S/g+_i^JR`*mmRT3(farOFf3:>poxw$zj?dQME31)TWL-2oj18Fhc>K(+[S?n:JB/rs;;L3-n8", &
        "E:asV[J2RY^((5_v=g*D;5(7XzJx^zQw.O=[E.bT1r2*=^AqB2bOA[)ZgJ^oZcf:0lWH%y0%8S:NNuc%:uk*[%w556(o7d$i(n3nK$z`0/MV/X5*@]ILet", &
        "bC?BYEV0e[COzEAAo4-avP]@oq)eX4r<6X/>FB9tXV3u>QD:*^fx-QTAO:fs[+$<>3bX#wgewe0)3CFSc749hp>TXh8:7ncRye:$q[7?(@oD`Q8z4j?Taq", &
        "*M>tp,D=+R@PZ;6f/uF*:BS5MPsr$=siBp,*tGgWp(g$tW%S<,?+D[+OU-k;V#eOn^qm=l(>`2k4t3hZ<LoP<sE6VrWMt55+%=6JhO.w1M?(_XkGgb8*]`", &
        "RhhOD9s[(U]$Rc]SgsSmq%Y`,F73<sN;rp27>NfTmhh)+MOPa_);SWBNzBzZBjiIfKn?FKI-)f9Qp-F6)>A;-VJ9>e2Wu0Z9)GGX_xc9r.MYt4%NOrqz_q", &
        "vnUSJz[Hdhm^QgNq,A[ncQ>jYCR4]1T1%Tn.s2Fk`kM1D.$y<R)V)^M8`Dj,sSmY8=UBx%#VtT4wi)qnV9jucxTHYlzM4x`eBq+cU<6AS)%FlEEMEwc1_1", &
        "wmT_`aW<liYY###-jQOFUfF/1b6*P=[)5M]AuPR3zROOT83z<)#O0TG%sK?^3cym+wIAxml7,12a;]eO+/X2/z[SmLp8-O^zU_A:pYzUsW9D,hj:r=pZ<]", &
        "SUXP0l7y:.,z1H(5aVS9A5Xhb@D`9iQjh:tU4G(,:P%*3uIf0E/.wCaSSBAz>[U[WC#Eq8W8o4a`(SB7k3#jOZel(:nH+k;]:B3Oiv*(#^_Q)hKHeA0W,V", &
        "@@Y6)<r[EOAJW8)JvKr(.3GOn4W#S*-xK/0SGihb/ov=J7stZ#nC9torRP(1@uG8wO1L83F^:Q:lW(L:lpb9gAUTO@BNGO%]Bt0j7#o=XV8xo$g(Lv?]q3", &
        ";P;#heqev[auS/^p:496`A8nkpME2#2EhG[dF[4WqecG*V:F$hJe`Zl)B4W2A/HgW9Q$RaH)0CrP]hN-V3ms%:yDE>FfQl8#juztOfVFyersLOG.c>@Rd.", &
        "%d]fN>qPlaX@Um5POa])x);D%Ov7y:kL#.NN#Dt)het0*J9+::_llZ`9wUkhtEcZEVoK(`5IG@0(4)yZPn/,_YCasHJq*_#A-3)$v:)#iEjBf<HckOb2WU", &
        "Ku`8Pu-[^$e0bp_]SKN)T18K[<Rr]Djn]rz*Ec-F0+i=M)nc(<oDj5JhI*$*%w6ZqTo=]6PdGh>w4ARxuMo$=PEuk<L:o0H_h:$9@NWf$4nF01^cQkTI+(", &
        "QMW5h#hB(1wPm/_xZymu+Qj4q3YKW3b=s828[QcFg`i^3lis_J,ShPl$*k#wxt-e^e4RjubgU.3$=r$wWEX;lG.zN=qP9IO=@99vDF,Qu1*:cwA>AtsY)=", &
        "%*Gl,mKI@KUK_[OKk2VvL;h)yjc-cfk(?SDh.S+l4>7K3%KFONv8Tb@sg>gn%y)[i0T*nj0^[ZI4K*mkt;kb70bsV.kN%g5SXpNq8$t^=42hVVRD=D]gig", &
        "V;8cR>dZejKh10sz:sj)n85l12cMyvmNEFV5HdsZUvJ9W?FD5lm=N/J*RFmtCNOIBQ=+Ba/=>nbHWjJ(ccn00(n7Nj9lW4F1M_Y]+gd5;k0V$owlLfwU^P", &
        "ZtymT?-17)@AGw$+DF<l286fsqP(ls[gBB0h-uDowKL>%Vq<uK%O:>Av+*ud+lLgI7SpJ<^rIGPjlJErR<LgmiX0G2VF5(E2TCl=@fj.`MyYZ-lX>O=8ZH", &
        "lrQ`]HjMY3TMNmBG0.WA*Lv0Wp11gIQ)U2)G-=@T,S3x2Fi6CyDlz-`Rh$k/v,Q^f@q9*sbopl5a^U$eom]T4%RB_yPSPSQpR$H8;:UnaokbcV=$dC8R`-", &
        "?jyA[bu6pLal/ZWdGm$rv-%Mpg*$<uZ494/j@<fXI]G79H>Of14jIpR1iB)w1RtcO%ehwIl4;]cXfpf7hVMR25Z6DG2oLrfai5;Ez_`45?/>ZRTVe86Xq%", &
        ",Q^kf7qVMI%-;Sdrp=lmTC4+x<VyK.=c#oO(kpifF#zXcN?D.g9?F<w9pL3FK#b(xcV8d3$7eQ-U>D;%)^zq1N[.-x^yjuye$]-T18@P#Pv%HQw2ZM%?I2", &
        "kyH;8FI7`-O`H%RoA(mbvNc#f@x;>SnvB+]>wLJF8`Yzn-#PpS_?oE(^nom$,O)-_=ob4$bV4hBe%g$w[XWovlm*q;9^(;17><3tv?+v;uZWLKR-N[2s5%", &
        "?NI5CGZQ)hglu*H3G1ie>fAP%+88DkSi%_h)bgH%6vJoFYs.FkB8j;Q8):V^a_HsPBMo:,fdZHP2$mG)Xg`1+E=_?(W6f7_:Z8E#Tl76bg:sXaT]^($?NS", &
        "5K]g5>vaOQi9s=FC65m$gRY2swe<zM1SXuYRi?]nQ?1[p2(8Nc35E(bxX/0IaG,Dk`V1PlA^0b]Ivuy.YOAIgN9=+b`@.:J2,gD6[,mEtbqvp^2[l]4J7)", &
        "/[lv^_nWXGM@j?*B_ww%R;m@BExx-S1/=8R5Y^FfaSwJXWO$.*NQKHXh.d_@05Ncr=1XR,%b7IhT+Q8Qh[+-H=e^GRl1iZ=PF$?g<Y[D/@h`sztS$6t;Zu", &
        "pKDuS$>ULus6RAf<yC8?+=$]Tcw43`]l,0I#jN3o(4eJ(C:l4EIb[MxC+>PBhN>SsO`xU]Dl)Yu8Tu(AmPn[Gl0C8ijWAGH>O.m`wNjkfDJx*S,cYxY*+H", &
        "j>.I7]^=k2],,w3e.S1Fa=IbN+Vw#rCwM4b?goQ*Sz7<Eu5V+e-kGl$XE,s2p2Lsh):=y[/iSvv;5ARv<d[y,%sP.=h@`y[irg$;QqEZSq/q[1qjgZ.gD4", &
        "]RR,B*5G@4Nf]Z<n$x:P=;Bp1o4mY+/DtAaLG#T0Iu=o5We/Y0Iu2UR[03R#3.6=K[+XCdrZyf$CmVFfR]nd_CQ`$.b)Vm`E]=F8tAqHeqF(_g0:6Rg,lu", &
        "xg),ns-(zCl9J@op;M[q2Ml(QPmChFBpVBL9S6O<l5Uj4QSh5H29.>FOesK7Z>0+XU+in/s_@G5PAz,edbb1f;Od8;6e/bPk%AFF)9,j09b_:sT^OpAD1v", &
        "Sc6]<K5P8jI_>swt8.5TIaH2TEf=M(RO6vThg7NCOn$:YIOeKs>;*[I;f*$x^MM6DiR#-ncDE/GRU4;w]?-+@/--t0+<=MV80/?1PMKO#QMe(^@@Zp_aG3", &
        "CNNG5Ok,=l,U//%n8+P>Di)%J[=AwgN?gf@uj>,T/gMCFk=fcnfpIQI;kjJ`9g*RN7Ccsf$v_@,1j]LnGEUb?sJQZSYW_pw/V+V7]S3-IW.nn0=l92sSCs", &
        "J<88i7Ywe?kNS/Xv0Q9Gu%EZ4kePEr<lpxqyA<%:Kd)W9_/iYIE,cQE7*0=rxNbS(ESkfpCrKnjN8bO<1@IzXmGHu3@R%;^^91tkJM/WWGd)W-/,`,dpHX", &
        "jvAv<inLhGG@5@o+9k8)cwEE-W*uji5*uaWNxqIH-xi>K3Umsel[4U-q)SkRao7JVw[YO)%0v#aWd_^4Z.Y`L4vj(5nj12I2NBx/<;VT^fMtA*+VyD#w_D", &
        "fn%%?`Y1is[CcMFJ44trNEZkG[:BH9b4L%P,rB$=.$Y-4Vg[+J6CXcW%D1mYOR+BLimD<D]F8z%RH#%Z4dT>,Gd<Hy3E`fC+-[EkcNmk*n3*lcxbte/5,U", &
        "QnF3*Wbb;pvQ]PEGChKUE-u+<-+87C/0I1ty5J;oL@G*5NDpC(6j5asUmJ-FdqX;$prE+45Pz7Q-ou%=5x95jb3R72Ai:=5K+o_qAVqPO`m83@PmC_:Nt`", &
        "%ROjFPh0l0N<Kq>,A_9+1J:gF)kp4w<#)u9]kO-wdhA(/n)gdF<y[WN8=yg0MRZF*3BrUIZ/z`Qq#l84Us^I3mpqI^*,?i6-DlyBOKpEKMB)Flwzpf+X<N", &
        "Eu]$H%NnDz*-j7Mg_Yds[VZpYM$a[hO_5gE_lq]6O798kCGkSDxHGN7g-5gLN83<kOOH8J[=qzkv=mB<L]dfX1x$@-6[RMzQ6[.W6V]#ooJ^563=(jqlrG", &
        "`_2=n5bRs%d-N@um`xFW@#zHhm#7U=@;D?JZ/Lh0nP`1[?JT,pz%nct)C1T-)]k_SF+u[[c]dU4h:80Ff0ir;`vOhpcF%17b[/o=waeu)3H0[oA+JTVtKh", &
        "A,MRX1Ami>o=CFUPqro]2d5Vmd)5V[Z@%d@m/A;ht3Y[h*R@`#^dN$5=V-0E^vOVhdMJ49B34Of-/>-]C.>g4ffu#F45+axOIs,cP>RSXZ7:AkSi#U$u#^", &
        ",to%?>e90E3lp/K7b^Cr1*O$>DOmJ(=V463HAY)k-*OYe7w*nYHOXCWI)Lh0+[/ow^NOVS.Z0hJSpx:rBQJ0-(uXbfgrQooKZE8Z_ihX]IKdPQ@1cGoCAe", &
        "fH_=[NEqJ6AxK(AEyE=22S2ihJJ#7F%X3<PQa)Yuid+$G<W,_=(t$ne8J3w_:7rC8*aW9[9StvZe$K([pLFO3q;fA#$kVEu-hipr3UGW/9/ef,$7bWnLqe", &
        "mlM8gAxMp_@vV%iXiu$QRYt.>sbX@]B%E.xkBeh<)WRtidW8e`z_J8JAM`gq)2C^zp7?^.+d;jCxT#,vn)XP*sl<jNe@*7zH3X(9%<BG;2]9xFLO?vgvOJ", &
        "FzS:vkLulN+4Xp/9i5MOe4Z$s0/]wI95Rf7b%]X>(-,WK6Eo9dFb]aYckY,5>_PY-udLOPRyr5U=Dgfd$vXx)n^A*PJ]yX*AxRqkur*qW/r64aHlMZ-[n7", &
        "_#P8#o%#roxk)>I*eZT:oaKr,JJUZ/%0kW1k6vHttZDwKwt]gMV50./x-C[C9[$kS#oDFX5w@qx]se^2M1r2_+:fV2gx6B(`4sHIFe_PZ4ik_CUwb1;]o;", &
        "mRbOVRHrLhT`3pji)/pYU@I;bjc9UN@BQg5[t:[s^<FrP.ly`3N=ZEunT+1u`Hi9f6kl9W`wLNh>aW)lt_R9qae88A_f%MRG9xQsd)gsF8X]llvH6poH^t", &
        "E,R9Hk24o@k)bY%H#jZ2g(Na/n=Zd>.eap6%V69-8E6T2HncXU-)NsIe>9r1I@:k95Z-S(bEIRq7J2-@5$mPaF8esR4=VGG.9IqFr[6PzK=1:A]*#t%uWG", &
        "iw$`#C.?b+xv3l0`#A3#/zjgHV=bZfma,c+;ZQ6^xCUf]tyhbg13uxb$3L^w2[`@+F5Bgf.wfI>iBldC??*:O7vW#9RpU3_?gHSQX`2,_Np]v=0p?Ltk%%", &
        "U+Qf`r;W>wyq*^:)b9lTJ>8C1,^G8kO9jNBj42^gU>z/L1R/uloiP0$:tA;0ZuOW?=.1Sn1IhwPjz(6Wi1BHJ/PJ1drWskRIYJN3a#T(U.]aO@S`GhldWQ", &
        "wG*AJ9gpb.1>rA.uhsBQ*f(S$+C7lj(#,3NtaW*Gg/oEiwokB-lnxt?h1W3J5cLvK.RbI1bHB@>c9/yTf9xl8ae4YpWEvsVK7?C2>):E3hViQ^47qh)VG[", &
        "@v%h<g3ebJV*:9Z?2cAjl?`1W.=E)W9k1:bjo$jaZ^,E>*@[H.3gs=aLG:clq+5lnt#ZAZr/bI[;XibOf@E+)uY*n4$Iw1W9g8<flxxXTAe2GdFKI>iAUI", &
        "T$`BAsv^.jlyr1EL#o<L+X9*>P$_1t._*6;K/?(5dAu(bq%RKcli]>@;@CIzSyQky-$DLcL#bQ_j^gYr`l$D+`]I9M@t,8EI.L`i]:wr[5^6pC:L<`b0la", &
        "GS$6Zn)XU5?>*2qG3-x)V.ft_%d[-C7A-I(=>r-jEuq4R^Aug/(.4K)gJ19$8w.edj@TOJGDo0yNZ<42O5#m5SFZrh?:1*U-pdWy0m`w^)irF/Xp:q6fmR", &
        "Dacs6(]l[/3ANHHnV4H(%u4Jn-*vn`i;%h+r3H)aar6ajPZN-:)M,Qi-onJd(VX(OAIeZl0yx[*7j,Ae`;Eo?ppf>)WJ+#NecF<`AYjA/C=a95)/jO^xEO", &
        "t$GQzs/JsLx#q4JX9xR`/^;<0Vj(>B904rRN:ufohlvo/+fO#GT^4Zf3kQ.:1/w@oL6wd5>lSvxb.>S.#PKPt$SmF4cd97MI:2r?gnz%la.h(hA@ts9R#w", &
        "PR[H;FhTE*hbE7M(xzNm^$NL$-D6+WwzOOt11^-9K)n,/>?Z;_rtJ/SQB+.-ABfB$zH[XNn-hRx>fq0)jj,;^CjGWm8@lpts9VPBy@WO2.YsH6@o-mk`P=", &
        "Xc^-bUw(5>r1FerP#Y9YrD6yX5(Syk5yLf0#9Nw5+U%+a/L7o+-6=`>^l]Ae8?R;KnkSH$LWZO1-V5g:CgioC)QodV$.ku`a3;c0%s<8s=AThZSXE5QLEL", &
        "w%aseRvEc30mk6g(XPUb,U*@PR^w[4Wv;2[pcPY?4E*rz>uAwg#rPC(^c5KL)g$*ZT/Gy;4VsCPqt;_[z58.t41:?JE7-j%NEC%%c4Yk_C*:vZ*Ts>9C_Y", &
        "cFIm2xaPUldl?lsVNJKX@Pt,YSi>N^JSAFe4j/Xp9.D#+_/4O.lc?@Ep#5OO4].hjL6I#lph)hX>u*bX,SD8%gZdIOWw05$0n;wQ)n:#sAJs$EIm*[o(Kc", &
        "0NO=,(Y.tOp%pGM-IrdSZJuY0iXRP2gL5,Q/)toO>Aj)w2Dy0#v#)cGi#:Cu$eO(AhNe0%1HaW)z:.YUfOZ74WmoR=9K-[5>lo1)B*V5V[]u-?>`w*ZT%4", &
        "[#qwh;Le@x6we%KgR3XKf;%.k$a?%z((YL:+iDEQF1X(4S^qUkr;$Ba2Wmr6<EXaJ[xI02F,Ka3.w4m34wL-blsEv/NwZW2YNg$7G.wNM^::e@c?$#k^;P", &
        "hYO<v^9jo@9K5Zb/%dyJ84t=R.+R?V#Lb1/DBDIyZfH8$I$z5[vaHw%/%?_8Njw13uA6:kH<rZRM[qS__b3>tBO.A`87X.w=8T.Sma9l)=8Env0pxCQ/EW", &
        "PJ*2o$?kJSAHD_5B2`oWlQpY1G)GcG%qKUa9iS:DxEIKTu^:)i)+e1wxy#-5ln*chu(d2%gFksR>x7EV.lqvXMv1oBRc;,STSGNK>gTsTQVKdk%4.3@Z^P", &
        "sv7dtVAE[nz%la.h(hA@ts9R#wPR[H;FhTE*hbE7M(xzNm^(:L=a+t$]69?vCh+yWhFAW%)#tb9EzV0%TVkcf)LZ:L)FR6#-1;NDDGX.kav7+Zh9gYcc9q", &
        "UGgseQ6Jv4b2JIEvQu-@Y/NH.n/DLC0ss-+zSK$O+>-$,u2RMb@uEq,PW$[fs,pUAn7,?w?0xLtilEe^1W(#6Eh_9fmnO$XYXSdhl*sopbYil-6?3M1M@e", &
        "IT?W(H.=;9A?mPiSUgtifeY6*BM?1W:)>gwl>39z`rk9[j4_N<tzFL)o/g[jMWl;bx.op]Tpd@jAS<5iwW*$b6.n5_Xq>3EM=e,o,KWavF79*;v;`A6$qO", &
        "06N%0iCN2US%AkZ2wxGTcueuIrG.)JkqAAXh@bVMn3FCn(D5Qu@#/v0:5gu]77[QdejCQb4KOt>@t*zi#@`?NW15w^G4bex/Ps%iV1QK44qd$0f_:,D)2,", &
        "m83j4=0W*_jR9(2:eINFtcC+2vK`<>+m`(+e7ZsIBcAXL`U0G4N<NBI;R9r2>%K]OHk9dO`lW3.PvNSKa-Es$)_X$^T^[9.qx,<@ScH15QV`<ZCMvP#$A)", &
        "pnFGvF=7seIE2bUNG9p$K.T=T:7bn2xBJk4Q/D*wIEI0Oqskm);=^=lk[^H0@mJq](?y=*TTc@r#E*n99Fn[OCJLY+VpAYKb-KZW_y05.i.yx/vl^;pVa?", &
        "V;=7xXK+pAuOrnT9Emqa[J-MC[P>4nR)/uwPktR-N15;/FG_7TW@66I6(vAlH^lua(?NlRSo.nPGm;0oCnUmOvUzg+@7C17H]?^9^$@[9]H%zGYw.YMh*E", &
        "Y=<%cH<(*1[%lf[YT:?#Y)pReUo%#-DHToU.MKthXK%q+(+OG`FYq]PMllK^@RzIU;#Zn%4z+Q0Ay*V$pjO@)5O^$v0[_D$,9EIOp8jYYg:]S+NkYlfbK@", &
        "rGvQjcAzLAoqY8()e7q46XzuBss:LBIXmvDUwq[X[6#k`GD#mUAV^DL<+Pm%bp:b/1[;mp^lLMV`;i[$3/0_x0w:Ui9[89F$].q6ba9]A)$koR_1xJf=N5", &
        "JenO:#Uqvt1A*k)/ihe^+v;X%7:8T+zM]npZ:#t-?a`gPheEbHtG7LurqNm^$Gi?<vA9mwd7YQg_%+RYqg=JvD0P[Pa?Nq,gq3@7iICR@nA.X_>fAW7k%$", &
        ":q$l8H]@;.7C]E:Cq2UEt^nQHw?Qbo0(ZMGVFp`%%r(J-(YMrBH2NMAFwrt.ME8w]I327*C?,wC+dM5g?[mI*BQr0^bGZx$7s2YNRXDs*HZVW1B$%-9add", &
        "$RPMLlMQT(DF`UI<Zk0dQ[,KPGdjd34GXYQ%@3YV;2%G]@C8`VA`$5g91%^b+8/j_yC;c7?@$k^52@tEyDNcf5kP5J0J#zJ[bW=oewVXi=7r5X7Z9yMfd<", &
        "5=yNk,^*d=C7-G_+Vr9pPtwS[hkFe_PZ4K;N#std5EMK@>p6/8bT4nO$qj8?1eJ7hO+C+=/k^o$iAyDjclv_1d)5XnIfOBvO7$g?[mI*BQr0^bGZxX,p9T", &
        "SCIGSCuLGG<>KQ5#S/0r5:)WZb;.)^m2^V%2?/T:R6$FOu/6@n)9t9Hee`<FCq<ZPq$V6D%UV3U;DBzA.x>t[VTJ8z3xRK]e`IJwO_(s6I$skJ_z<].<h7", &
        "1U-Qqz:I]*;(DC8tK3F0_Qbj9b$c1;=:E6x[d+C+2Se#F.uhOG33rxJpPoeYF<f,D)iW]DP.c2@YXIwdSWabs[ulnuoA]_gF.mP>m[9RKZ1eOtequI*@;3", &
        "R)JB##pB2_V5T8qvv;5b/zk>P;<2Q9.AXs5m9@xBv*s?R-7es(*K_Fn(lZv<pTZ-nNNYb6)fYyMhY(UdQLG?aP[8r3OPl/,IP*##__/9%,5iIr3l.P?.c;", &
        "[0,SOO%c5gM/C:%g_p9Uy6QA2[TVt_69gx@,+JLD,:dp$Y0<gqE9B6UK4HS`5vnF[n>,i:FC53qYE$xJfD>/I(AhEL2lyW^2N_8nx$%dNZK)=jp<R[iMB7", &
        "P+cJ]^RI:PzacAJtbRe2SXQsF+2>;I5$$$Xlf]irV#qe^%CGV.)62na@92untA5DOx)D:+G,YJR)5@hB4R?LXHA^t/gor:@jQOTW/5y>6GC/V+%**[94gM", &
        "UmB2Uh9$o,7*CKR=4qaQ)JmIX,w$+:a^N]X-YBCbKlvg=+LRNFW3^=YI3?5(M--SADklniR+F.CZCbV0w0]F>f;(uH%qIahuU/DBiAv+xpYV)2ry;kuUyr", &
        "bSBG)%ctu.yYUVtMi(nuaq`QtL/Lp<JgPf92yhU@Vi76Fjr;k_D5^CeyUwbJY5<H-7p6o%e31S3+2.(V)#meqa[YJA?EPwDQYnWgrdPe8*L%$x7KimTaE-", &
        "PESJS^djS/Ly4>)F7VllvEK=CgrTSgZRZ?lV<DUG@U@Wb*mV+C)J0U3$2?<Qr2zQ0JFvjwyU-W*XodW.7vWD=O[gIcjZs:Z5K@h*MOhJZLfh;N]RyaZVJk", &
        "grG-IQps`.WUHV2qR`CusWP1Az*p?bX7[n%EfC]URGm6rIYnMjT-[RL-V`kHE>-CcZgQ:^M`1:ucI/DOQFDj^:H>`N4(_08?wU<K^LNs1<9pL.Kd5<rCqb", &
        "4)Td92C0%]//7UX4[<6C/j@uJj6mM,-U_8wiKe*NxpWrU%b,)d1%z6ghd*?qB[$$0pfr@c#?Z?%mry1(T]cFM6NA5igcJoL?7^*=R[fD-wf2-TVfvRY,Pz", &
        "_OPU6Mi/1b^#s4p;rhUJ%dzVgD-zuGr6@np/ZUmnBlfF$?ExH(L`^m,;X%7:8T,T^]nkN*$m5ZGBEyTif0UHf?^-a[$G_qjYo@5)NKEAttJar94IiK)W2M", &
        "Z+*5Mp6;ksVe*o:?<9qC#TvC_%6,93ay#j-5Jkt31S-$Apa9qT)-KO?AdDnwv38$Yz.mo9dVkDW8(EO)wAlu_2`HLB-iLI0e2l`9KgrFvEgCAsREqrT1oe", &
        "99vZY*%Y?bw0hyNF`G4Da^-A7#@p86kVbhlc?K8GP^$^b-,LLs^+`u]%hx<%m(R.3j/f8`qR0p/Vyp7M$_:*$C+n>/#Q-HGyZ>rs:`#%(2T1cNTWfe,Eyl", &
        "0j*YVqRr*Tg8B?AWnR2=%um44jY6a`K2$#m.)UEmU4I<m.8$Yz.mo;tLsn)Wb%K.5dh)`q.<-eN=WFmY%Jx[-aK7/0DI7LH(G(65[r*4M2jM[o<U7MvCH.", &
        "eY+eqMq7R:A(?O6Rf;_ebHh*97YLg2j<B@Q78v#_Rx^0PKn`S](N8+pj?9#k/[Y)hDj_-9:$nNSlsG@(Xh]#k;v_X[YWv)nx(%c5$/d<9#k>i]of<fnX/+", &
        "+0E-lq;gipZ?9BQJ/segh8.0%2gs2+V,QwIRy;>x.9h<FY$=^OozYcxO]Y)#4M)(GW@y6#4oGy/?5dLx4+d+/W5P]3I0(7z]-ZY3Cd?f(IL=4WbiIWi@]d", &
        "AWoenLansVxx[Skur2+%Z3*6_cAY2L$_,viYMvM<NQtYE/E#I`4Lx2KQY3)%s@GVDiG:hrJ=AkFLAl-Mo=;f?UEK?`$b`M.ao._-XK_=OH-,v;@BR^d3:k", &
        "VEO0IOp8jYYg:]S+Nk_Bhm%<BEv%+_fWC[2A)CMO@YMCfcz,op,`-4/_aKne(cTZbH=%N$ygV)iy?qp1_dBU6wSnX-5#>;;X%7:8T,T^]nkN*$m5ZGBEyT", &
        "if0UHf?^-a[$G_wDtSG2k*7SBGL7rz5ikc>Px82<`RVAQVS-w.g8S>S]JZPP:cBr6u#?q%AQR>G,P=X/8]l1xy@g_E157a`>L8Ug,7uk+S]z@3%H.Hl1)x", &
        "k)gA=sl5((:lax6]5O:Q,[i$5sZC$Qi>t7Q:vtR*XtMp9y0q#rIKOkoi`fo?.4uWa@M`L1d;%iB)_G9HM7N.[9JRro8D@MR7kY3o_UpddV8?JPzzkEdm,X", &
        "m+qwOoDnkl/7oi@/ay[%(RPIYkC*ha$Qg*tDMg#=SEh0u1h8-Rmwr@8G/x6dD-W)CE.2vx3EM7tHRLphGCdyfpmpNbk#oM$P939APZ5vYUb?NaB/`I)=2n", &
        "<`T:Tto(v3;Ic1%qfeZA9.,y(NeAIA)Td]+:+Ty[d_d(66CP_[,.%Upkk-m7nWOR8QfHNCE/9:D8Bebtq@Gn9817bjJG9H8l%mYZP-m*_$<i>R*db_k[[R", &
        "O,w7Td4yk22@m##UGna?`](+:*E=Hv7a`H#:*=#mwDjx+p`(/VZ_DFcswK9S:4i+-q%WqRqY4YnCDXy`A:_Kmm]DzGc`QqYRRLCDdt2]]bu2OM)IMmXY_=", &
        "2[(TDQ$X3lC?b+xv3l0`#A3#/zjgHV=bZfma,c+;ZQ6^xCUf]tyhbg13uxb$3L^w2[`?n/o=E#muf%>[M(I;ieJPBb+4)pGNOusNCO>+C6s)si,87X?oh)", &
        "`q-S5x6a<3iv>/1tB[0AIG,dItcbfAp2hkrg2;L$QK[Fle,cEcZ``)B8%<K,OCotKRG#uOQb,qeJ@AgC)wa%8*OA*F3b]%?PFBZm/C_sAk(n-tkEMhrP`Z"]

    character(len=118), parameter :: BLOB_ROWS_7(100) = [character(len=118) :: &
        "LFT:3Rwu9]e_PZ0N4BB)t]=9l9:uLw2$WcJw?:Z.:TOL*MU$$0b)hZeg7@NghY9>akPf5ck+^A6a#j/X%,^>R=JgMGe=FX1U=U<j%Bb:RcXTiG873/Ndaa", &
        "_`mjUYK)<F+Pv2.J45iV0J0Y3t>O-?rJOGMhTX)XJXkNgD<SJv`K:dQv;b]sz-EkFAid<rG_.DS>7Z28rJFle,cEcZ``)B8%<KQykUpWNlToC]r;>F=*>+", &
        "*@[^9ca^@vCh,[.[kUAC7mD,OV_=Q(?7u5-6t*W:=z-.*r%C:XL%j@f8^=O,rA^eJUmb9$[`R:FVZtb7/-?[rW*HO59]ea+UQhiubBQ9W[+SCvPy#3AZes", &
        "R*@daqpLlsS%:F>7.>Ye+V=EwFLq]*$m[1nk*N3Ch?z0mRDB_kpb[h,9dz@R+NklktR]zmVK$E#eJDbYDY,w[KDS#eH0*lu+j_WITPXGIlbT=[pZHbZ5D#", &
        "AWD-EUGWFTJBNBs]GBV^.BS5y:Y.#CdU)-Wi9J2x[pz+n:JxM+6Mp$KdrwYG<-aQD82]i8=zlA]8)#foT2ys>UDQQpKELXSa@/udwhAN6o:^^,?_[KlNB7", &
        "24=fGe-a$Fa95Ir7*2^-OGX?5s>_j4JzQ33Q[(7S)TWKs(VJ/ZXa1K,[oX2B6%<2X6%-=S:7z6kf4oodN?p:nLwYlaU?BNMIi:uH4roHMAUoQWi*RK:^.U", &
        "4$E]kt7%_;K*kO$qNh`:`hfIz4U.^_i*2phxyk$fqwV[4JI3yN5A)]6BrwvtkXARH:KG)=L[uGhx:$%by]akh1b]Q<BM^(L`*kK^(+a^8^?bJ@I1ul#XqX", &
        "YL+rN-%Z]XZdg4d((0^(5cRR0DUOi:Tn=G$dc/L%mZ=c*moqp(YmkaPfBYw^ga7IYl^hzPiJHx`v;Y;]Sdj]8C];I+8+;i;7XT>SFByVTE<3i5G^5?m/jX", &
        "[Q(ajW0H<w+dwILiPeQ[W`NE;fedni7RtidW8e`z_Ioax,H</w>hN-2QZ@6Is)e5aipVB><>14se;T/laC#wr2VqJQ<:-?vmD-SJjA.K6.:zXAY/Zh1DO3", &
        ".a^HG.v37f6GoQ`iB]+MG)@sJrE1=TXDN7ppX.Ub]pd4ysqx40#J?#3HNoYvaSPD-f3xKHu%Tlo1)c*V5S8BVY$(m:z9^)CHK`w<quh?ua->/9+jGqdh^C", &
        "4iaR1v;f5gOg4e>PWe],C+4fI/SH%JthYAu6c5Pa21SoJ2fSs<V2p*r^-@rweP7I]YdRx@/1Q>s.kq1u%_5h$D(S/rYp;9x@$n2eU/XP2/Wb4M.*Yh89/@", &
        "X;PjW6^qw%(mnLRCt4mArHE2yEhR*KVS%zS.Hd6b0G2+C^%eC:t?0c..+R.:^Fb$ti@6O9rRO5Zr_d6,qX^7rG7Pz6_8:;T=e%)W;?lj8qAJPGkd,-vT=1", &
        "vj-]nY2Y<V/6dxJff6841_YKDxlc^$wpbKM@K2J@5*oh:``htcZ^j$f`AQG2pNhaO=4`e-^K9W6s+yw=MX/2aPR_]X/VkluYniA(h;>VEZjzNglAB[(DzD", &
        "pf`2qw<*YBm2$bn%<yqZn:%;z$(-sg:mFIQrLsJ(7-UTek=tkkU1E=zt25t.nbExdIYf8`$(1c>Z-ePbO[5qYiexG[@O3#-I;>LP8KdBa.Lorsup51w;@P", &
        "=`o3Ur0?6ioI8YN%)$J>:fM8@+$#$82u?crtVL,qZ[0k]jrM/_A?HN>lJn.9VK0;+Bw$[jkTE<8$iqSXtB0XaR6IUztg4.BXXBdG3*kCkGHp3AAwzj=17?", &
        "gvG=-UAK?81xj8In[4RL=Ul3UbI[t6Mi>r1.H=MD_MVT_d;NyF$BJ.1d<tujG_+VrLwNJP#`%@LWu*j$1I3cL3w+6=_``_CUbi1%kR-2?Q`,FO5hATfAHw", &
        ",JNA+7a`?tApQGJ@J/2kEp?#;@gJU+z8TPX?,#_1TF6$hd[>W#.wTB1em,.`bRA5j)s-G(>y6eQ_0J+CkNP$dPAb%H@`v44^J31#JxHsO8^^Dz/x)%-Kx)", &
        "$Rq)j3<JYr-Q^6UMS2;vc6@Vl#1Rm<[4>ZHUQfW:rlzkq%rk1E;7:u5c<bN<5T2tfL2*F7^spr8?#J/(6ym`oQVYRhZuEdJ<13-I<V[mle?.rKNZsLgZgI", &
        "<]mB,DLLTNjgIh?G$txBvB;L8Tc+M_ng`?uzOe+g9:[i[OEO.6$K9Ux@b(a#z?Y#e,4)AP]j5O`HgN$:FCnGCcc%M7)-Hcl$/eKse,f5?PP1bGd_1k$T(L", &
        "bL+FszMv_=IoHh]gP9=sl_^(j@U%bBk_QTDny`-a1^$)s.7-w+nIdHPGS<G#C->D<zRU?p9A]uc4*=mq49C?z#(KKTMymbt;RJ+XeP=1G^C^38EI*rW$K0", &
        "in)fp`Hc3,PO_;E;^t.O>#Rw(.;mKYnLGyWHV$.tc4Y9.g9cx:iz/*+J5d*Bk=OOI^Dz/x)%-Kx)$Rq)j3<JYr-Q^6Us+Qu)Ep:_h$,NoT@iZ3%:^=`$b1", &
        "[](;-*IXVfRu8:W3IGnXm3N_+aX%W1a@XQ_aa<^Fk,+;c6#NzFEw/LlGZNi)aM`]yJqUR;J/FefDC[l7B*@Sl1[3c>p+<3irZ^ZO_x`v;m#)(W<4j_]ekA", &
        "*g1ths(s+$h$9UQ@EZX0D-Fu5%`=VF9TtZ:x%_[^X_UHaR#qjAz$z^wJ`BHq;s_FG3eJO$n)+r@)MJ-]$kgQlVI?]SBWj;CyD7uHXrQz%v+n4]+_CY^0.%", &
        "T^`XHp$gw(E.H.klR]nW($Pe<dQJ6m$XmcsifDtzIMo#L#pr@b#%PN0Lg?.0)Los$e>tGn0d0xQ3IaY2LwxF/z3)0.$)f0D1m.9[U+Gj-Sx$gOl/Yv1i6O", &
        ";o>@An5Zpe]3[geY;Atp73t3W@%5%h2^MZ9,^<-Pd=eO#CH0=1V>^;o<gJcEFY$6rtWV*oM8BA5LS9G#pdIn9e#(heZWtlYBq-(_%2?MIKq2M0SC>FLIgm", &
        ",pmuBd_Kj[)Wd-PcUr0b8kW2awHnc/trF>%`B2gO/)7qkFH=o[)EFNcK13MO3Sa0)tP[]jFiVvhbMnaCK0*<3]FDt,F(`CJq51z]G?il138nS[WLWFcM%Q", &
        "D8k(6h$*f2jjrmo*/aJ[xI02F,Ka38%,b9BB?-blsEv=1d(W2YNg$8=0d:D]ry7Dt.,Wu5)EQ%s;<hh.Ed8wuxW^u*YX_UZ5?b%h$Duny4@G61UV72@5TB", &
        "Rz0K4ZSSj6^W,^]_ET4ldkd0kwe0plZ6K5(_%2>wUadcd@A$znFN:%GK/D74:JzZBo9%iwSFcxI/M3,@yXm2D0$msZZ@L]1Oi?bSCTqeGKipnR%:#zIuJX", &
        "8BMf=44M#y]b7Kdc@t,8F,d-RJ3hAdnF#-I[$NT)RNbNwRADX^1NL.Ar)mFUi9XJjQp,5q)FO5U9M4L<qaLLvb#5sJn9@+2G4HnB$3m.Y<THe.0_lkPCRh", &
        "cyYllg_gl/99^JJ?lwD@7M^Jrv4wE$1RYOnZRZJPBb+3H^u^:F.VSd=fnI.vV)b#FiAhLiPw1x$`Aw>xws2paBTsM0AY%i]xg?R^^oUr,70/KxD7DaZu90", &
        "s3?FivqVJTJiF0HE_QyBO:Bkg%`p7>O=7dS.eoOEQa)BGGJ]`PEynH-%qL9_KtPwfIh4YifQ_)GSm#;opV3Y@XX.iw44@L[fXmz/86[Dt[z,7tpY,pN/Ij", &
        "q]pYH-lB;qmx9]Ac*Rj7tLJV_t7fO/ov8Eq-H9DX,V4^wb1.u]a9BMf=44M#y]b7Kdc@t,8F,d-RJ3hAdn<ujsX(4VEseWeU[GaQ)X9oHSfwOfYxJv.*6F", &
        "LdznP,:UB5PG;GJ:_bQskC`ggk3u*`K--e9bi1D%<>WA-?z9it<_8c+b77:mPG]9Gos*IL?6t5]?L_5g8*iFeSRju?lo=8[GUhJ-@F0h07@JgJZyMHOQOx", &
        "u%;yU,v1G,Bivy>mPFvPy^0C@o`iqVu2l6_1gH_kx+[W.;%oJP9GGkyHv^6X4V*dx-+*3ryX[Fy27NMU[JQJho0ov%qG_7TVjB$zbR6H@U^qnBG(D0WCEX", &
        "IfZ#Q)eR$,7U=qR*aZHkD>9O2LX=G^Y-9+ajrqU<[vuL6d=0LKk<PiJHrA_@5b[W3Su13@pgW3^tmet3>BaLq?D)Fc-pakiyZD.ae4>Lq1q#c+ubdm_hyF", &
        "HmEPp6t)nUN.O0o9[VfIn?ALav;`=7w<2awc6NSW6%palji9*;d>j5cH$JN-,l.;LVm5r,5D<)1Kmv1?,j,vqeViu7Hatk8/W%m6cHZ^Tme*F=X>Ahb/7o", &
        "=ih[2MF/leasu3j_YGYRueU_b+EJOGaY(u/AH%%^E@Pa[)bOGNaXUVAAmd(JL%pAB@qpT4kP5`u)j$eXjj3V7n8D/o]5pxLyiQ6DNyXJmm5[nb0JZ>2gY:", &
        "ZV#aT5>5`Bx+Lj5xS4=U*7ZMcs?<Tuq*57pVe?OT4w6i-)]k_SF+u[[c]dU4h:80Ff0ir;`vOhpcF%17b[/o=walm#f(UvBlEI$?JV:YSASZBRwpk](CC?", &
        "h`fK+b=GwZ[+xB%=usb4@%=`+b8NXbn:2,*b`JmKM2-mvz$eDx48Db<ce/UuR+P@u9uvif;i(44ko[lKy5l8$lsDCsx5M28]_4eft$[C_%B)`DBdLx3a>e", &
        "w=eSQp)=dB/ll+iF/[-)-F3<=-y?>Q_*nX^C=NFIY1A:w(0#PS,GA/J:+7[MiPtU(SyR$8KmX,h5+E<7`/gW5oD*i7wQ=.36W1]wT9+]u>OR82]Jn_l2-,", &
        "ne^6zNc1[A>wMJL%=S;sN^z7T0$$.MJ[BURmCX=1[cUDLRr,k-V-fpGpr.xIY-wwFi@sTVewmHPs7Qs-DNU?09rYq1Z:k>4^a`Qt`[hWuH-1#R6WXagdHW", &
        "jC3B7s;ebtqA:A>BC04hyk)OsL)x41Ba`dD8XlHf]4:`s7fwpb1Aa0T+;8^(-:n[q8[R4QH2UL[fdfnx4`+(laYGeYre3rW+lotM*U8Ug*LrUbl+#ZL30*", &
        "kLei[<p1<s7%wye(k,XhRF9baaU]OZ5/GVFIY-$;N]odK%3meM:x-m*GMkEetc*S=M<tAe[CV*EFLr:0Oie357r>.-=8#hpkjX.2I+9-IQcE$jK*2HHerv", &
        "jDJ3EaZTfQeuSQNIMzpln1NdH;?ZwbFuGmWJ6;NkT5p.z)E^7>qY_KlO/NhNmp[7<dQ0rMffg1BuYI9J8e(xtCO$r7N7Dt.,Wu5)EQ%s;<hh.Ed8wuxW^u", &
        "*YX_UZ5?b%h$Duny4@G61UV72@5TBTPCDPna?<=?Zv0ALtdde[FrDI`Kd6-70wP1iSX0;/1b98U4Yp8o2v@LoQiVJBNd8vuYoVY[i;po4[/U*EglvZ]uAS", &
        "%4>)CEm;?>cfMsAQvVslqhAAevS]OMiK,f]bk6%ww@/p2=bgJxpX^>bU1./vN3D1=-M+jKjY)2KcfE`vn:>vRl/;NWx,K]]V3t[V)OedX#qUK.tiMW8x.v", &
        "I<Iy3WmlfC@`(.@5#qxgeASAuKc8j@:X^3aGX;n2l2Ym%[n)x^FV#ca`j=FpQi8Z?4?.yGfUe762w:OLh3h%X:CJ5rhli#Hx]X<pn@fHOf_2MC[1ji:Yk+", &
        "lgnZObMmu3D)9q<`8:<?+vra8F2:W+RPk,%V5KI8Xli64]1;#.]REU]pNd3eUp[I7QSjI[eq0[*L,=F8DL(%]oE4/oXEft9Z`#bIX)OBPI%9O$2=kA/.cY", &
        "S#OD.T/w6hr$>h`^@+albZ*1uUULb2Cksj4oP.*5359l8*]F5JCOq:7]Mf*EqO*7c5Cerin4Tl:Wn+)xjha+Uy4e^;`%i4/d+wEciYHS3PGI_$gYK-ol#,", &
        ".TJ*v8ZBYH+sV]2rrU_ac3y[3f<56Y6lJ2>O=#%Sr$,k0+Q[B,^SW:ur_kuqnQY;-i8++K9p.9[v^qQl=oYQ%ejT5h?;(s3%_F9$6sm61L[2ggIAYlz%2M", &
        "o2gP>b)0bI:gJTRc,7U1,,KOvC;2Gu%[EC?OA[)h#3hl5Jv:,h:7x>pACVWZ<+fB[,0fjm*G%PNKh-?7=be*Z/.bN7d@mCKW8;0kp;$?e0biH[/z1uyee?", &
        "Q#I3/7]Jj2#@G)C(mL_.jwAGs6x:7WRv)O:ds2dX6Lg0<<vh1=FDQ`+oTnp)m98,j[hQ)-*?1vo_Dd^cy@%$k0I$+S/I0+1xK#9_Q3g)XGkMb*#+Yf9T1$", &
        "<)2tp:-[Capr1^q:J`eb1Otn$*`M**jIOH=9:=i/K1=Us4$Gi>XqQ?GXWY]-^<YsT4GfS*MfyEG92W0b;,X-o.FY++Wcwj8DA93DKd03(FDdygZ@B@PNR3", &
        "GSAFfu?HmhDBPKaM?5X1bi+?;7/d]Pf:ad4lPGRRSD<,Aoky%*Rw.H=8]DLuZaUh(x8-qBMh=6dvX^%hA?CM*uhb,h`0imKn)Nr2p>fDems8rt(LwwlN%c", &
        "ig,T5teUgo(AOAql]bDSxndH16Ej-KJMBZ#.Zw:]+`#^[#bAr0whulZrfxuR*[x*2w+7AFBrF`<iocV;7@4Gx$2?[2Oc7wI3pYuoSb^+8T^9T?7_hdJB*Q", &
        "0/`J`/y3IePFWU;JvKCLLhW(Q<bKlgunQnd0OY$%*?:_=R1r[^8LNT<6n+]rhnzc.vMigU1Uav<f>w/);RKRnAwHv@HPN5^sEDANbAn(K_`r^,isA3<Pp5", &
        "-YqAPaW7Ia?JnUVuJ@l0HWcPW+LLTP>VMltDDdb=-B1]1LCdWF3)oGY9PJMsvBf4,@w<ogjCbf=i#jhoO;msKM7H)3*s6$:oV6G0aiva)<t]IEO^]myUA)", &
        "C4/v%rbCSYZ=g+%L;kHI+vaU@5PbEDI,kUkc>o$AJi6@Cv,b,GW^5z%mA6)al6jPO3yV/gUKl0Y@sti)7NCL.7DngEJ9e-?*ZR%T26BRRj`zdG2WvNNr+C", &
        "W*0:#[:f^CSnQ/fan1]kc/m)11,p2vc5:f(dTBX^ZQXC^-HOE#*N[v4U+v/T=0JmL,5e3*4_<1(/DiK6J%98Pyr@yIDNb>eO-[,tWROYbU/Eo6E6xaItmX", &
        "*Z5ZqS:bkR[%`[+qBULGe$w;nZ)O)TALogjA.=l)UAP%j?hX<=HbRtBcsMW4oy-W4Sc4;tT=NR0%lXsHy/jl<p5LULKz5Hacyvo=3r-KWo*n.k*seRdwDJ", &
        "/9su<)D*Iy:J9Cn]L^oM/DpcZOW)77H==_yS14-#o2UT_niLi9[nnZlCagOndEh0OQ)n4f7EUJFtQec>p^^XP`n<gv;w1g`8<n=7XPeOa/EzxN0#Q:9e%(", &
        "ogFiqDm/Es)avM;Aiv(0F,gn`f_,w?dwBag/He6K2^#P5$V-Q)uhZ>-sxQnKcJ$FC11=n7Kkh1fKp)%<h<>)zi/YSMzxGWJmb;@XBQd=HbB#Crn[>*4B79", &
        "m)m4]GkpAkL[V.+M+>bsXkpkAbxu?nYS@/.kg*^1,yC3ssEb<HF(5GZgAI.^R(c)v+Ue@Rd6Zu8bNR:Sj4tKbLiZB<N/UyXyx71_^`#JLJZB*;/(jRL:FR", &
        "FcD^BOFXp2%)8Y=M/GJ5BJQ2M(^4>gSB0?EbCs)r277p<NFoiaE#*B8(S5ZeokXHV:7SciP=351?`,H)jL6qyn#>4CV6;W=O+M3@i`;1axB[OaaLFWpJwC", &
        "3y;g,s(HWY3T4Vs%agc2M;O<31Qs9VIt[-.bOH%=yf3;^<Vzp,iC_$ZJc4i9AAwUX)@fmm>=yt@-Dnr37OMTOGB=Z3l,4Jhe0#:O5[Kn9T5I%06Y/68n=8", &
        "fd1;e1^vbTfQtgb@#fm(UBq/>ZE#G#EM#4f8_abt(aY:G:3mRcM%VG*O>pWq<bz`<dXPyO5=d^MacLswQ*T7Iw#@r[oC$NbhkpDDgu#_0``5ViAf:J@.%c", &
        ")zuTG:y(-%j3^:fJd%U^qRQV)+:p(4c=rpS)K#Ge9D8)@X`5F=w?+BYd2$CX,a(M_3EF`1[cmzS*K0WEAVNOf92+>JWFcX3E+iyz4[84Y5A,Ah#8@/:L6*", &
        "m]_/]7;_tw=Jh]f`UEv%fjAz8i:wkObvjo+U0NDP,o$KbB[_En3sv9bPg+d;OsXKgd#26cwX_hlia2dh3LD5^7X2vP5:>PlPwT/E=7*bVj+,*dc60n*]eb", &
        "=o$<>-I]4kY12VM3t=sG6O:)7T0qs14w6=04WDm`)Y.B)CM$t3%1Z[:$QBUg-w<,fW`%5#lr@cu8v_O6sjy%P,Vm*zm=rOJRj_xQK)5gmI7g,LJKn>zfO`", &
        "we(OUNB1g*MIHRI94C/I;+yuC+$qFi<bSJE>a)31u<@iyCR@@3aWE)m>?N?UrKghMMgXgt=WyW]icr[MZovfNG`5RQgI.iB)9wS/-xgeU^8=`FcVgWk;Fv", &
        ":p<]aIgIv0(D6Z=X42OiuP69AuMV:aP6F+GI.@TeK19cki+OE[P2qs?pipLvWK?KoczC3j1S>6h;nZo##:T^=H#gTj.NK:7Mw(=b8Y^ip/rWrz)VLg.%U-", &
        "2>uLe(h%:9m`7@p*I/=1r^LdDQFf0GSi.2uR7*2hXG8o`;5h0I6q%s6EyPGEC=*+[-d:/w%Y[w;H+hdYIse%%%0M%cXjDdi5aH#Bh3th0K%/ib4?Y3R,pB", &
        "4TXDP51txGGAsN,)k@z%Y4yK4W%1Du4FCncxL9deRDdDtM#Yj0/?Hd>M.yStHl(5(Uu#A$IP_Hr`AdG%O^:<$1w[ZNpuYxV>K?op9nr.w<4D%=bWofn2oZ", &
        "tw/(k=afP5q+,K_Bi#lLc%@ZD%dHvfB<-Nvl7*Hq,@@_BaAArKP4^R4Iv3Zi+ZIAPg$4hPHq5X-SOfqmt;R``jbm4n?;^3I9m@$EtNrtVdD19`>DQtcaHC", &
        "xa%DfxlXb/Y-tlx?%`.36@r6Pc.1oP7ZX)>8Mm>,*;:u.7>v2f>3?B0nNlOf?fwbmHfMiGOJ*d_ZEHpmahRS(j7JmnGVK?>j?0)Lj16XXdp?)M]b>XJeAE", &
        "F7WGytCGsPidtgl63$m_IKJ<Ji9xv-V$=oF*?O@JR8.^@W376Q@klI)fPg?r]WNwxu$gb(+y=MGM4>`Tle=^V,pD4z_UPON(2KjijBgF+`RtkHL.J*eo]_", &
        "T1jt76q;[4QT$*r9Y]mkHs`%7Z]D<TiivfFE]Jdg4J32L0v[8U-]jpz:(S6qbf6U]%RHTKa#;e5=gm<W>A,Be.otJUf<s=*jp,uoh*w+L/7(qGfzrP7V5e", &
        "Ng^QD=y_Y.7UBSP/(**w1m]%:I;H+$z4;ne]L;_^<IxsA*svSDyhiVf>-STeO5vUD=y_Y.7UAo)3:,-$v662D-<Jov:^nGU3Rxbd(Jhtf(PSSZlSSv$3?3", &
        "eP$#rE3CHyyjk.v(2z8B8],Q_*H-F#O8.i?S=3m/5S9acbu@4%)S4[0osP[FM^y`*>B]HqIr_KqWONf:PXfQ.,echf.1/[IV^](4QGJmRfC.BTt#5*rin<", &
        "yOKZLDoO%]dKR7^;x18Gnfy.BLE<_uPN3riS7iNH/f4CuQawGIyx^C.BTt#5$D8[*VAPY1EL1g4V#=3@d=.KjJ3yiVIO#g)xww4leThu]y#wM:S[DV5s[$", &
        "pW*b:47uPg6,sx*5r..ea^)ik)Xa#E[JZ4b+Tnj/gIJdCqSRF13X9TKtN[3u,CjEklRyIBMA=rXd#J+esfTPJ`@AdG/3y[JSEC(J+oan-FAKMEk^e=25e2", &
        "zlCy(o`1R/AjNk/:P`qe=HW#d_yp1(+s$Aq806h<AWpg]?lhD3m:<Er-u?2G55)4jt2dJgpB5,@a%km>H3KH9_j0Aiyn2,(8A6YI]9>.d-eNoE0OWyOfdm", &
        "AdM]s^(gWkQENF-E;8EO`UMcXk;6N<SPPS._skWZ.*IpmAdM]s^+XBkPaLQP%,[u0sGs6K,%)qX,3QTKQ%NWejRAqD:YQR_d@`XkmJ[u-D^Ek;^BrL*^WS", &
        ")OT7WkDJ8P[:_1@R*dn`FO]Y$gQCag1ov8>baZITlXoB7cFRtDd-Em2vMSL.SlV.J@-F2Dy;^c]#.An3Ub)BVG.%iZ6VoFc*%kt0v`^-qGD+N`$cWZ[9ql", &
        "%oV38<tXPLpgX-hbslGCpUBcjtHr[[/JID/vPSb7j]RLBM+OtCs9q#WjSzTuEaN0F8G(4fpa6P?;9l^[@E3o4CVy/ip>``P^E@A@MwHT[4D6%v<4hDV6F:", &
        "9)L],n3xfN.@xB/:K]:2QOl6Sl=95mYKTMXTfhohI#KtWbfN;>5,3hDk@WP.=-:*_Ijuj]n/cQ;#4eE.P;@xzufkq-EzbKpJ`Fi->HJ2`5;u@8.$NZ)uny", &
        "qn;PX^@v]o^1Lo8^H:RTa>D=`5*-AD91PMpCvFOb7DI9*0=0u][JE>^@y5_m,P?.qz>qjh_`OZsM8UnqlfQ)#gjUffzzhasI.s_ZK8uCYO9GzB<GW8;##g", &
        "k2D3P/DUm9N<1ywyU%Jmw>YK+45oS9-3twLc5h#e/QFaqn[RwPxL3e^(sGf^<6O2R;ZbJX8]T_;Pa+YAWs+v_pyD_,KXGx>Z/ar7huh19IxkE_k50A*^d*", &
        "ClW+*iOSRBXhOV4_>9c:-um9$>0I9zlfMN<H8wtM(1.E@_EA.PUEon#KfWP70e`7pb/K%jup3pIs2rR-I/edF,F$>Yj7XE3w[+0GKho,QHoBUKB.?8^^qR", &
        "K$wQFSJk:C9H7,4QYv0mY/[2(MKBWlr5l(Ayv<cL:oGV3d0bN6jaqfM]Su7`Ez+JJ<Vuti.Cx=K6q7-?#E4IE><zHRW9A26//oAw;KJ9ZSDJ.,dmYefo,B", &
        "XP<vg0HPvX.O[9dT+F$z9UZHRX15q^c-c>EBCe]Cbr]9ysI^VTa(Sh>4]-Jc3ICSE0^2hnP5p3WD0To;a(kwmw_cAuep-L8F8jen$6T7ET-r5Wjcn(mH`4", &
        "[gds;yi9b%p5uHAee),SUWS__.3fMr3zEtXSHb9?z5rk3,?MG(.4cYPYZCQr$cKs4t`x0x:NJf>A%eS]]VsJrH,*4).I]cdWFU^n5D00G*`ScULGgE<cbW", &
        "W(f#M4;HQ8Sw,rm#NzaUqm.Y*.NkU-tj+kL(Ul-lvY/ynY2c3Hrr/RVp.1Pkg+tF0//MfS^K.gf9PM;6SiuEo>?nF$+bOUOA34w3hLon8syvOt.KMPl#Y?", &
        "z%sfDR/lx0:^Jsd?s]0?I59sa$G%Q`AUgE<4(qYG6#:/tmI<KY[gIxaFO7?:Jq[kxo2va?VNihqO%dyFR^P%f=Ru`uNv_zGw-gGpT=IJw;ijUp^ugN8cpO", &
        "Xe(*7Qx@X>5pmOeyPBe*#Q(.LNpO52YWQ.Q$X[uy2ZbWnaaqq%2F/-ycb4_XyA]9x8FUwm,<OFHBAe,jWOxGRJ/hX-*hax2B:w=+Y:Dlves+Rk9]kNuTBx", &
        ".vdRad)VL3n?LsDn%lPY:E;wguufe++I$:>nA+WlHL0HwoTiY.5o@[lWSYTeY4PC):yEcP0cvAt@%I(7ky4b.I($^d/Vy(SibanH.INh]92Rb#>n$ji]?U", &
        "wT%VV5+4@i%cd(`5D%H9YRD]HW=)<g9XpG4gU14@qe6CSTsN`W<mFz<hGn^e<3-rv$M7A7w*nt/qog]3[A*3j8AdqZ>4.$IEl-<Z<f>4Evw`D6Na6WBC5C", &
        "xKL4I9ztvR?y_F?c`#$2pvO((]gbE(^M7349Uy9GSvbkfTL;S1[xKxj,vDO-FYXXlg_mt1fYUqVIL$/<LVRYI24ni9l4^yRs7vP`*YbRrg3np*,fmL-Fp=", &
        "-l^cC]Q@?sYvegUWmi?)$n97JWCWfSlkvlS:G8?Yrf%nHQ@bvCFC^V]PllmFb8)TcM_5l#PNprQ)C-2/x8:Qs%iAQ@dhDhh>#NPn?aT*Dd_[[6^RQ9dl:/", &
        "wE:QR.2ENaV0TTPLll%?^.j6;fA)h*V%$>QVVjbdYO<hw:gH:E06nF=5f24J;mOm,DHsdHjJL-0ALm#2Y.:eUzu*CYc)7_PbqQ%w]e6+ZqX4ho4DQ8R;2."]

    character(len=118), parameter :: BLOB_ROWS_8(100) = [character(len=118) :: &
        "aSO-STo9n8cfQ:`<jt#0@<A@o(z`uFh_T$J?49seE4DqPKcq.xX)x=48Q$Ll^,dy;Z*/fV?0]g?NyjmZBrsYy=,:1tQO.doTloOFJAA/a?%O9e8GW-]vzE", &
        "d89Gg%Y%Tjq$<.nWG(zUoSc%4uM7JitgMlr:grw289,9GVEPeZ*9d8L6Y>gy1EP3pX%:*evKJ4R8$JyPIMXt1p#WMA$B%wV;?*xFcY3rR>o@TqlM<f)+`w", &
        "9F(>KRg4jY@E(x_Z7jG5v/I1+ZfvN#fF3W_,]bEdezKOBt)jf1.FZUw2bS]tjByW`+f=K#.n_h>wT*kk4b;<AS@eD/jGF/m5Nl<Rg+4765%kHFEM>ZmcgQ", &
        "q9OOMT/0JdWCNMH`.x,oo9xl5?,ETz0oV]U9e+U7oOPrTg-*y9Ib*GaHks(w2.@p[zKUw2B:MzjXPls/FIF:%17mVC7PtitilJe%:dPEOF?.Fb-Kw]e4@h", &
        "IlTL##WUV2(-Y$j$lAKpx`;:#wwYmf]0]F$pM5n@m-XZF)*h>]TOkdl@1hjzr;?`s$2@YP)x7[1xI%ETN`uF3Isg%Vir_50yfgjqgi2,jc#N-hn*L%.XW(", &
        ".vf(t]GB,Xn?pN<B*-rd:1(C-3f8BdQ$%Z#9uL^1)JD=9Nj6Yl^RD,[#e<%U_+nXk9e$tp>nWFx+nm#2iD0[0ilvLFsj(ls%e-Lnq/MgT-=N9v)]<3vJDN", &
        "#an<Qt)dMnFx2ROxu(H4se41<:HT@D7,TJd;N.:SieCWdNAf_/`8Y)]Kg)2K$v+OFBv<kYwjXf^(KD0z>O0bVU>O:x3R/QxVnP-]V4ePNm3T.4`<.9We+M", &
        "U9Hx_zN%^XnlZY$S%[4l#<1jcKlVB7d2ikEh1yo)U@-oM_r?<paf#p:)e/8VqoBzYIMCf;^$dlXnNys=53#K_zy(nXa7h;0A2-e0:W<T5Ht_A.u5+jmjQ6", &
        "bYpS_AF9pyJFSt@`cDp^SD?V?*>eCBV3,O[:u.WA;61?ho=OVN[O#TQ9O.`OlL,=pLnpmI]Ff,8a$d=?V<kv*9X8SBkwO`?:FNEieCr0DYebW4tpv2-9m,", &
        "qF3fl)#TtK:*u/iRn;9#4([RZYK_XcTYyH,fb-9mh8S(KY(.evHPMkU(SZ=c=Yp<d3mdEn7)CX8mzXOeLh,1Ast;Qc+T+NL4S=l?5#5Qa8?XP2_)z=xSEt", &
        "^)`Hb`;yFHA,a5?_Fq-yE>u?R/?%CbKJl3pI9yJ,=SQCE<au1X?:l>74h7hq-(MAM.*pfm)wB`@1L=r0edU*N-4Xp:rcQtjL]v#5P:^Vu$.*7G:s[w)sP4", &
        "$08lhGXl.3?i1o6MX,ee0TdX(K-=jQejU>BpX6S^Y`Hl[SEK^jQ`4NWB1ctl8(_DhS<2s;@g+rC[(R^v_iQ5D/@*fZi:%s%FEWpxD*AGMi;@iWp(Hj_^V,", &
        "boT]6dcsU%,sRk:[F9g`2i<A_:KkOPhpOQnV)ofg?-4cPsw0A#:07z%G(Jo/[j[8NDRGVcw2VxA6WU$]TZejlB(PaJzK3kYvJ,bnxis+KrJbPM>?,>%+7l", &
        "3:d+Ab^mJD@H2YqEgQ/_Do5s%INHVkbjAmy#1QFmm?N#inEE#d?`wRt$d)T<bh];e4mi?kiXSbD:em+s,lSCfd.%a,`L_2S#m]WHF,[?(zA6$e@$)_s=Eu", &
        "FsL>/DHnNe);b8Ok^k0QxiqSw0%JJDy5^%q<]g70@r)kef08-b)4a9(Xy4++s9[$a:DqQRPDJT0d*,kRBIRK4XjI^;<W26vm*4FR/#J$]vcsQCBM].5bl#", &
        "L8mjxiTdVB]8n4]E,pTBh)@LYBc@hRV2Z,e6G`o;tJTP>Lb2K/,@YEPi+AFhYBXC22tv<p@-u3m:PitZa34fp]Fh7J6*g`d(BReN#$c;vx<[1#x<[1#x<[", &
        "1#x<[1#x<[1#x<[0t/tn5mx<[#(diILHx<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<[1#x<I,8uc2pD*hciQx<[+>udU4t]", &
        "<n9$x<-hvx<[1#x<[1#wog$,StUH^x9FA`7#@5YN<BK;a.xDxoKI6qQPx2Vx<[1#x<J+oX*Z-TN[+>FoAPJ3[tB>Y[/*P+KUhE#%UTHM,b]S=####=/>tE", &
        "8##$Hv4I?-07*o3l<8_T[########################vAFNw6#######(aCI/oO<N=_r%N?Ee?NA-2hNAvJpSOf<JNAvJhNECzcNG+0-NHhl^XcatX^q", &
        "Q@Cd)Ac.i7*L@kHxm4######ERfysRhsE#HwWu($8I_sWtJi/fIS22?>QR4t9[h4u,]k4vlZ0:+8fH?;XnKDII:6IW,@RKUI@u#Y+Pe###############", &
        "##2qZSs$jA##2qY##################*vXI$wq##4-%^U/^+###+/#01YoKaHB<KaHB<KdwvXPpuW?N?Ee7NAvJhNjBo?fJZc6NECzZPvsmcPvskL#`.", &
        "@l[>:gX[>:gyfxdnwkjHaRpvQCYpvQCYpz(H-v01FUv01__v3US+(?,v3-Ls>z4tDI=v6$o*v61o/#g/4U:+8f(<[hXiFkT^.<<.=*pa09vqAgOdpbmz4u", &
        "nv[bs=FiXunv`N>p82W#2nVa#3U6*up]O#AKZR-vRzm5up]O#D(qi`FYJ[hI4zNo*AE?d*B8WmLH9y.Psc+8Vc3`#[5af_^g:Xn,shK%aB]xz-YS_(cu*F", &
        ";sXhlzNYt9_NYt@3O+AhWO-(m/g:()eNWCl6NWCl6NWRpUn5T]<4^nS(uvZeHpjR-cup]h+uy5764aGwI4aH#wsHOh_7<l8#uz)V:7<l<Z#=l0Y9o8xy:X", &
        "^YX*Jh_b<J[YD<J[YD<J[YD<J[YD<J[_K<LC@7AZ3bxFg<F+iIzvRiIzvRiJ4)1/U3_b7=`+<9UGhf########################################", &
        "#######################/$1nfCV5PnPZ8-;7-=;+XnBBr*5E#>HqGOp?HJ,<bvL]lUiDtJrkDv4$UO99lHE(b`[Qt5f$W+2WY]8xy1bEujQW.W<mj02", &
        "t*o=y?BgW4Ykw(6G=j5?$-lgbbN.+BO;31M8q5kUWF:yEyw>bx5*;#-_FE:dRQGpUsmLo%.6R.Nf_E?pt%Tfs;O9UGhf$G/u)9qjM/AXL$GAXL$GBh@6gf", &
        "nW6w#############3/;+O,qYw=D^`/-g(Yw=Dn`0k$*#######%Sn########*nVO=Zr#################################################", &
        "#################################PS4##################################################################################", &
        "##################################0V,He(1_E`6bKjD@)<2.rrkchL_rfO[vB:NGu15?$i:Sul3-O@H6?=1bAY*Jst+i^2H85^2G]N,F(l-rz1V]", &
        "v461Bo$)Ps*UVnM=ET37?5pr_?gb3e0:7=y$bUea%:;R;FtU5o/K@)K@;(s%%:uB:M@@v3fjpQD5y/wsA-/i$iZx2Z$n(/=kOh1LiZ9J$ZQsNiPxwb1VON", &
        "bKcG3Bk`<eJD/bDPXC#oQeqe;6$qe2F>KfBE4qeV-5a#RK5cJV@.oak03qg5msU6E3o(U]q,_`coX;Erm+`@UmmbV2XV/Tx9)s-=%@flH?_Wq^LKb5Q,+T", &
        ">p`a*LS/P-7,/u^2rcGU/QN^FQ1]jb[rTJ8w*Vv49mQPbOqsT-qrBS(]NL]+=3PWjTNb8bo)rHJjgxf0*nBx]*c<d70II`G,$e@]qm#VT0jP>E-$B#/?$h", &
        "p,Fd5$%zz3/ne[Rlr<SfP`KELAhLZnkHZ60Nb:@9ens>^`kx3v)DL:BHIo7Fbm:YcRh*Y*)b8Y2s=vEx[`liT;;A<->9Y81C9t(JwZH`7F,)K:4.^<[<$F", &
        "Q[KPp-GnX;I+cFppH16nC8)ef)X-^/#XL]MMm?7ZNW?^JM^h=8#*LMMZf`mlQo$c.XPl>Gw@i,a$P$r3jc/i<gRgt?)Se]LM>sT$llmXko_f0$]*GGXVDY", &
        "*tIj+5y1C75c>GD*O*LC]3V`RvffQ6ZvSV.C;%Npk6pgYk7RoWC(6>[(i;<AMFZSY[6Op(PkL?UX9,K#k4wI*GsKHlVVxJ$msI*UR;6GeVoA5qVq9#Wh+u", &
        "UA>YIK:VZE]l5r?->cw$tTL6;<)cq11e5#-[<0f,x?C<ccvo1#/tX5PI^>$zF[?:<[60ewNQ<+th?=kQRf0E-T8MN5J,^2tGivi$MBl41c[1g1sks)VUQX", &
        ";1MkwZ06ysjN6+x-B3nu^/w96_.zg#[k?L2,rU<u]EDWmg#N><8zXVDJxycSyZ;]mgYzd>VDBH0`YF>c:6,[7$H.G0f-qAX5uLdE@OehT$ihw<N(TL[`.e", &
        "w<LNEL^?QD#JSIgUVZAZ0MMyqaOdGV%_>zY9<PRH3[2`r;@Ee1@00YKBDl2L:1E/1TZQ6/HGq:,<*^rf>MF+WIZv[NO]on[jGIfNt^GQwWRjk?hL3WV7eL", &
        "*Q%vNSb1s)T<Nm8mKi`@B>E/f.XpX;1Mc<_,dxt,-EKmlI17j.3mQ2Oc*<@<$NceQ/-EE*;qBl2h_lkw#%iFw;B9+lB[`%K]13_^)LAis1q]guPb-5y0;1", &
        "@-mAD1GW^X<Rt^`dZOLcvB#B9P=gRy`U9-J/97Ogu;Il/u9w4SO[w(OFw)7G)9hS*=k5@uc.yI-u:tbpNH5*?Qw_DZf/Rga`(u7@VZc`RVZE]b?wv1sL<E", &
        "=g6Nln>5s1GBiZVYG=k6e=;<9ZjFw;DZTR;.$3dCZjX=PGQ;WlFy1=;wq0$][C=gj/-vi-IFiWL`k=k5@s5m^6ET+sZ,<gW(q9u*MUF%zFd<PFXuTD:(u(", &
        "*@*W<P4Lo0f;KJ<P4Lo+kOd:]XGz8Dq4`TQ]EVW/f1YY3^,*OIh5-`IL0w>7z1+2O`a[#b=;#cF+u1b>9=*o1T^ES+o)r:I640VoT@$(HZ0EypUHVPA(pV", &
        "+4(4zWpuHno1inA.TmHv*FwFIW5y%-Xj.o7c%f=,sFw;B8Q%nsV0S$U2iy>uDl/(to*)%HYkx(h`kw#$SiukElirDRrQl$UzGKu,ib5si,HZA[Y[ohqore", &
        "m9xQXs(b3,fyl6j0*OK.54RFBYeRGxzkHm:Xl8vg?iPirDXz_^)AoGz-J4gw$/`F(LCtgQ-7lkxB9Jt#?v^g8^sE.^Yn0p7ea75j0kh%Z(0%f5LRcCffp2", &
        "eRoG?aZQnz5y1[(+sEr6rY]inVSkFrlY)RC,,O%q4*^J#_^3%R2jB4blFr0ed=-IUZXt_m)Dfoj76fxWUc-kC+kAYYK/Z7:lcPo_)Ou-gO3,N/HMjt^t,Y", &
        "./BO<%@;<OdGpuKkLpj-rf0f,b_`O4tk$`ywIn]7vet#?wUVoX#kNpbe9GyXlhkxB?=3]s]_r=]0RGE.T0_BE4ui=ydTf3r_h>sLB4GY;[EGkO-gVZ_%A_", &
        "YMXKVqgxXGbqI3]erNy2Q#;@^[:.%SSm@Urf@V%O](7,Gnlmu[v]CnDUq36^/:$b6Nm^VH5TAd?g`BG@-gJTFIPD=U,+_:A*mxh4nHk_nlZqGmAl9n8zIt", &
        "yvlSMO]LVBYX,w]]9tD#.#y=TQrK)/jKm.CcFqE5a]T,,%[p[<WG.=SkancBSHZdBK/de7)SvU?``+q*FNFue%f6g0e/EateFiA7)-[kvu*91Hq$-(cpS)", &
        "6vDI0k`$QmC^.rBtANPM]iOt?;xpc)bQCmlHIyma,l,OvYZ*?%sNI].6>*a>U.dQke-Oe00=%`1,HKO9CV)0`+hl>#3tDisPnBisPG51IAC$:@Ja9kxB+<", &
        "%XDV[O6)nPn?9x*A*Cc[f4.$Bm4)=$ByC/F%z^2<K7_A(r401<O9*E)Sn=44]ML]88Zym$Y>*pFZSP+aY<$Bu0<U,B,DB6qj4KWRX4hUeQ(3L#/NAgx0C<", &
        "yd.Ox63q1ZyS#VSX%SP54/9d`VR$(E`vwZr++$X#UAiZEvR%s>vIn@Yf:;yM3??jf7F5s;ehky5sS6EGq]1j#S)uNxpzKHN]5$Y*>y#y8m+ua_(mZavaQE", &
        "x9xH1M).:%YFhe9x_;l7p[0C$)_(?G)lUF+v8UW=iIc(@3WTIFbwBdX5v1u)9hNb=kCkW*9jqCHCiRRDgNIi@5:Gy6Nm+d6k,3oJIE+g9,p.pNvBb_8CpC", &
        "BckK;(na=m(izY0aD=@-J].42TbbM*OdUZd+Fq6Z:GYa74D=CTGnCg>r5]#jJL=DpD:AS<(kRY59=r5:ZFxGlO?fo)$=sJlpQZY0=`vZd$VZE]ZQQi/b2*", &
        "o->kB0IsDY@+b`.e3GTDXj^[_s1*5dIKA@Oa0a;W4N;QQi/b$EfXTNPLH7tPBM(YD_DP[PzPz4BD:uisP4eZR2.^>K8D?e5aVm2PcHK14<Ii_;D=]5yfd9", &
        "Ald1Q_pLn#;?jU1B?]k#=k2y@9xjJM=vc/VUu?sH*q$;DVZyc8(vwAlv1TG#0eMmZCA%>D*1nz)Bc77KqOY_::@1wwVZA0W*@lMmZSG$P5y03^5y/yc[nS", &
        "pD@VJeB5yk18Q*YdguCE>i(#n8jgw$/NZSH9.;;Fth5kZw5ZSD[3PixQZpCF3)+,vX=3b=%%s;W[.vMY,7*LKE/FPq6P:njPN+KKUpB0z?Ed+kf];2C<NB", &
        "eG]]ueQ)b#CftEAOnZvSlF9QF,;)KRjkw`69ET%7?UD@FyM.35yj^0Vq%9YFx[d4W:FZ4T)ct*F(I4b=v/)[kw#%e.Ez<_5y0%UisU=Mky7/Hi0oln0f,p", &
        "^j.7`rHar9U<gGK*ZRSPu*?e<8T$?Tu5X%bu7GyO_<PFrCt`;jLK4-%)=iL4E0f+?ZTBp/#QRW++6CBjI:I2*695T#Su99AwkxG+*isQ(fg1I3cEy,aukv", &
        "y7T6Nm+FkxB>_G)iJEVZEWL=kCb9fW:XZ^;Inc1t#4g4/d3J=wgP=PqjItjyI4M*od.aQ+A78`3j9m)dZe>dX*w8:FO*6VUIxu7jWZT9Zb_R`x73QS0??%", &
        "ZfJ6lVq_g0^YRy?FvW]jQQ;cd#0(v-_^)#DsBu.D1ia1OLyx*]QW`J]SDZ3=nN<w$=[z;a(Jfuo/b`;b2(EzgAE-K+]0YrC*j-7hPfkd5%+X><mq*6?`R*", &
        "mEp]x-[9z#KEH1./L(vY]=<P4Liudk(T2X??fqwp8F;LpRoj<U@n$wCX2v$OH$OnD%mT)hsdkxBpN`ZVF(0%B.;,)7,jmI3^$*?%Ol<LJV/j^lrp.G]dCj", &
        "Zv*a@J)NR/c-1ytX$WliSU,3I=hlFL6)>7eZ<<@u@YNNUEQW+::M/Tde2*@/%^E+JMQMDiy?<]YzuQ^2.DDGVOb]l[.4NV%+e+[6NeW^-U/Paa)Cj:GyqJ", &
        "#Cf_E%$bf/On-`M9r<mA><Oy:yUI/%c`$4g8L=91AK,[?ID0p>VuQVVjVx/,yu^0$*+o$M@NUmLv`=Js20e<qtB15mpiOLhqpo?PMuSjeyWW2)NK%0(fFi", &
        "Hf)AaJl.2@/e]@WaGXocf.9o<8jk=uXmJ7UO5a`[<$e1t*tk^om8A)L4dSM7y/FmoK]oC9y.p`OzDau^U,,,TwC/T+xta<P86uo+Iw37D.+ZtXJZNm;Ag4", &
        "-Y;O3<N*RI::Y1A[FM0E<Qsoi^TH$795@8SjsQ$Q;<9Z*;;<At[l`^#Sx@at]pOz2too=Q=(fw?^`5*mk6gJ[qe?#PAl%D)$J,lbG=K4;kU0]oT$D#mG)X", &
        "mnl/Q*,TRjr0=iKqn/ZNSL0eyynsWUjOE@_8PhfNQsl45iN/SPLG0NdY1b+=UsU/sIgT+r]B6QjWH=nrxX/LY<n+K=<=r<9#$/E$gQ]?0yZSDZ6u(8109(", &
        ";e/(E)9YMiVo-$Fk/;it`Fw8qrO4+=u47=iVh^$;;<B=l<Yx9<NS,8g=(wm0yL3=/7brw(#JT2w^>=RgeKDSj.-GY/6L8QA+0Y<^wn>I?P2>#O<IzA,57x", &
        "/,Zbj6_ZF2,U4ZQ;HwCC(oh^*imft3fYq[cFgQVfAu^WhFns55@4qW`OW7_f`q-dSviv*@+t`;Q;L;Qa$Kpz#yeo?d[2sv($<;a@#aT<biat]h4F2psol#", &
        "k3SCkj1sJJ)c9)nBq[BEr9K3^tKVMni1X[o^Zh;(5Qms_8$RYDv@FGr)D)0nSsD%]oik<J8qS,n3huX65y?Y?IsQ[nmE;[Q-a8g0ZHCsA28ejhUB27hItW", &
        "GR3nr99NyRN^;`RaXn,L+)rkVF+nVSIHkP^,;V8$l)Q(TP,TkcLwrsg>%nqU/YFND+Xf3A`=(cigY<ffvk1Q6h(-fZT*<lE?Ge,`d9o<(,8E(ia6?_-=k5", &
        "T2%]PusQ;AN[ZSTIK1#2NRIKl_^KAj_u=rT<9^g:s7JAEI`ZSE?.VZ>wdVq6Hv2.[Bd$+`Z6>j^,TWw3d+76]wn7)$)8$>lMR$KBt-/YFND*6Z9u0Uz-rL", &
        "4H8fTH]64_a#284LgMb%YGO^*M>_l,pN<%UgQ-`mU%6u]7;G4rtDmyX<i<e8tS`)Yb+,vgH5p0Cfov(lYH,TPQq_pAF:+s1-D5n:,p)1HlZo5.]:A><CYq", &
        "SIA=+pHZ?yV3d^6am:Z?1Y=[S^V];+,Id[$mm?;3PnsdWneF6MI@M=7%(=9U.6h%ayGc.rl)n[tYX95h-Z]=V_Y0)axNoCTs+K8d3]7<bYcidz[_#82sjY", &
        "O+h9zaU5C-snfRo<klIIyLxU%w[SG<uxgM*_pmpB3l:vP0V-MMg9aOS0%W%0?LC/Fo7kiZ<IiM6F?e<P86B9,YP0hzKz8<P4Ls0fwKE0lsv[Ax:nr9gNV*", &
        "1cBPX@;G96=3OZwMG#SW=vT2H;<;rU=k2$S$r;9)`.].k?Uk6)4@x@@FWGKJ8KxJOh;[yl6gkiS1L5YQ1POR+n6hIlHPR)KZQMGnRYQzVt`:Kq<?*Lf5xj", &
        "2dmU_LX3^kE_2A<n9[_qF7mpt*oY-gPaO.+fG#j@1OKbmx)uB,6XgO(lDJq4R;_^)LCGz-J5,@wA2`wL:Cb8FY0S?AJZFx[#D>T)P3u0f)0PkT?tgi=J(.", &
        ".nqr_]+-pX9b9.m>5RHnt<yet9.,K$b(^p_Fpo[FR#Kv6<?p3T9$JW];bkVuB0*mJq4XvqLX4Fmra,9]#k0+KYnkx.A9+_`]G#(<gWXibiEs:1_7]p/ZFv", &
        "Vl+wKyjgLUhapT-#kG0XbX2=8+Vq8#W8iu(o>Pvuc<28*^]A+/5[vT#-R5Wa(YkQ70TFt*g@,B23:A=uC4.TeDYFx<DZup/Ei]A@?l@_]l<g`3kXMe/#m-", &
        "%=38/Zm.ojbPn]y>b]fn5qYZ:gD86k[s:$iB^)b>8$7Qq^8]d#7#s66HVp+ZMA[8K;GMZVnhGPrk)6ciHU>:@m-:%p4D?69>MIkRdXwisQ5:JSRaKb=WVW", &
        "VZdCX6`@0Uat)X/0BmTzVm`i8^/)<w8#vu<=vAJ,0r6#0#lIv7.09*s<P4Op1GWZ-5r$XQ,#yWM^Yb(f]@j.W^YQldi-]UvG)SG/[`_kq7+0yU>zU-A,9@", &
        "u)A0MP$CwK(v%zo@bT.2pBPMn8Q,;[F#JieMg#iNP:K]aFh>,]Rf(77pv[BzblP-#%^_(FH^=%2=V<Op,02%Ak[Xf0sDZ`-0j>cQVzRHL-ZO6q,s66K7<5", &
        "ln6JJuXIu;;hh8_;><xVV*91;xS$x1o@kZ6REG1ZC#>U$Hb4>DR=U-.JksHnVdqUAQU2+;=.1yj@^SWZVm4oKTqzFFWFeG2OvD-<^R0[2%jxt8BBAn[#-w", &
        "0)M+U<Y.%4*@EuCkF%,9GWk7eM9e<-?s9D*zRwXhoJ(c2k$ibu_hr>wV#7=TD4,B%)`xnq]$^Aky,yeWB1*DK8Y(.,G`[Jn<(yOHx6Eon52ZS0m)xJxpRk", &
        "8zocsm)*-WzW4mDSu7VsfM$CwHQRs_Qb<@HdSW;QSC,9gN;u+C;FE;LLlme2[$;A?<`[$)%l1A@sH-eQE;a9Gs_p1ERH6F`@P*<P6ziO]AOTT#^XRmj<xE", &
        "<NRPAPxhEHr4*H$EnAPeb-AXX@uk_ZXiwN7t%A=<.y%iM,Yt;:mF;QhRVg9h#gv$)-Z*hGu#y4nbLo_^J^1%^A-ZL(PTN<MsJ9w8^om3SsKXftTz_TA^;E", &
        "6A[uD1aHbdNX9(:D7`,,A`qQXyM4c`dx^oPO*C,laTK+.K/cQ>kma-H]NmEui+)g8[a?[nEvU4Mao`rkTfm;Mk5rK%.llPFfM[w<y2b:NQiJov>6(NlCBb", &
        ",0;KbL^mbc)2nc;t<w>[3G)I];z3)Dx2`:>uzT/HeOykT_Qol.ni5pn,Uu2a=G<Ht./CUod;%KKRe@Q1SHubEAMgFQ:$77$-DuE^bdx78t@nfB+sq<@%t_", &
        "?.v?.$C4bxmwb$d7cR1AniXI];1ft5vrT<?*AOP=fQ@FQLNjLy245Cx9fugBh:OqRR<f2LJms?zeC1x7*B]50yIK^-5R)tulJ5@yyQOZl/$dHEl(yB`IR^", &
        "x#;>?q6=n/DCq8@xvp.g-J*7yQ(XL>k(_K]Pt^e-d[`/A2M/h*#KLIhH>(1T1.EW7dr(dz4o]DSokmS>r?*p3@(U(r(*w,8b+ylOXnFRg(KWQu((F3]HGn", &
        "`esk_([J*bIU%/ANl6B9)-zp4fSn4t)J%D,.3w/AA[KG=$AG>N$PL=M[>V#+J]@Yq;h-KdB=F;)uj?bV8*Tj/7Q@WL3pa2-bsTj:o-v*jOSL-cK$1]/.d$", &
        "EM%Vh_FL=p.NARTslen2,EPJqQyHI%tz.yw?OUyzk56VSru0`F@5OQ@J]hvi8gIzmKa81=Lo5I%lRYghOFjBAu^u8=whO,Q*OGFWP:C#8^W%L%/6(u0j98", &
        "NUQ/:@I:/Rl-tQB#`eS8[%$a1*Q5XrV+8*o?tPieRyBCb+,o@:S#y19:v@c83*5;/qRyuYz[mWrP`Kd5fPxMhChJZrty33h`cgxk%gs-w#a(b4J:TVIYw?", &
        "p6j<VLXbvSyNb`B1$x?jjjOE=*+LRl,X:N9RMV5PI:a:W2<b]Suledhy<l2=2S$0c8J2T_E$]uvR%d2S)@2T3e>7DhsO3(eRn_mwIZ5yDLo6LGVERYDMYq", &
        "6Ga`T:sEE[B<0I;;zWW.IFe%V;^2)LDh_P8eWc+;9[m)NFxS4ZKdD(gOmdn<tyXkXJ.rv7-^K<w`(b[k0S^._>.bWG5DrV$ZSg%2@Sba:QPb=dHnUi2s;1", &
        "<p66i7C3nzo:xP7nAIT^*V(1aN@ZqP6G.Ekfn%(0W7I=r-^LX]l+[kN=Ra4Fe8sx/D*nbdw#BI+I[RdikEx@XV;wjYiYG0DQY04kt=s]Z_dFw^Wr8%V-W?", &
        "rBaU1`,R=mG1,n<>o9x(2G6..J9DL^S5P7Fs*B9C4DKkM+FqrPpxHO*?4iHyH0#n@c<Ga2(j=T.9,0Cqwp6fc3q=oPt60[kGx/TP*1dqZ9>FouDDeUlQW5", &
        "H`QBa]KM(Gn@5QO?pAY7DWil@t`z^E*LcGDfsAWHg5q#0e8ObH$6?NJwBAGtN+V9ULD//@qW5>_oS:6c*ANnNLCdfj`P-=s57zZSA3x]8uBAPLoXb[0VA-", &
        "^94<Y:UozHb,-8Eql?Cv%EmknmaCTd>=zerFs@(Sb*dEXKd`;nyNk.Vk6a:;bpO:D,vsW@6O5)PVF34Sd_y+E0=o9VKSN<[o/i0k+Lq.Iv-ogF:XJo0sT#", &
        ">UeB5UjS-sW96[.o.BMRnIHNAa*=s4nPiDDAh%74`-qr1nC]2>V?jON?MES49<r1HL<NKcxhJ>CKa8Q<_A;/D3bsM]n)>sF#rAUty)O6vEpN-1[CzP51Sw"]

    character(len=118), parameter :: BLOB_ROWS_9(100) = [character(len=118) :: &
        "3;*AFX*$f>HY9qr4e_gl#2q/Q3KjqD3hSXAkJfWOj9T0aGfsBDos(Q_0*#v[9zPWsDP*$1<nXP7^q/hM#Um/X*iK96/xZ/*I*Sw=PT,dz/s:KE^Tas:NLL", &
        "nvVB`6v^two9=^yy-1TCcxsX33AYeC5U6TgcJ0U=lv%o<K:nzZ<1)bugk/HKW6/zcYf$,QeJK[:ZM.B1J/D0ukG2?6*._?H0l@_4+B4fxG`>):+-jb(6_;", &
        "]pKq>$au`O9K9(Ds7sX8voPZnEtu=)Ay8L6G$H>TS02r7e=2`[miV^sR_PK#]1)-pR5[VDw.)=]`/.<iyYG?0wb?liRbAJIeKWgh`V#cb2FgTOYkW0>8s5", &
        "rG#8HOSunw%I8UrvkkEGSKpQa]$EUyN-9#2i,lv#6c??$`lpU1X,zU-[5EQh/XXz?_dPhEislF,1W64mWq$xw]`g%7vjV*Q;uipeT8[WoTfI3GK1GlGC-O", &
        ".OALv4rbuq^+,S6ue(>L44p25Ta8Nk#JIno$abO9-_(P`N>io*R8cjnz9%^44Y_X:ugQ(qWmxWbA*LRQSO@Y[vNNiz_BMbbTBfTsB#1n7B;yu,.CLQXy@>", &
        "%%VikpHU730(D@wrt1/jFVHhtXX++8b1G3gWfR$p08TNN?Im%gD1HO>d(G>DC>34H6vyo(:y.li#y9Z1:*B^B:MAv9L%ua3<,$>A<H)r94=@fz78-0`lrL", &
        "/gYTQHq%I[fKAKpDJ@pjXR)l4b_#zh8DDP7BK6rFRJ$6]2IsM,s0-x#G/).w-%NBkVk#Oc9a_0;m<[U)NBTseQ9B,a.#Zitzx@.$x2fA83qnOArWl?AfHd", &
        "*qda0hMZS%#h1lR2Eyz]+$BH+RJyjP-,b4ddM0=8nR6nat+E<%HDyj<@59tP-@hcR$J%Z2K8vO[]F3@qDAwsH)_fGc]hgs.J4iDnQ^[hikYfK)b^Y8sQIh", &
        "PI/JQfQ7>07<)bvpvywA#1GYVI>ZukKwnlRa`e48+FV[I%)(nLKkGX/ID9ty5H`8cqNSNEX8m6=RM((%YJ@UFq+bZuTe[E)eI1C$32#-Z5^O/2dTsj/hf=", &
        "u-?S?W8)GI0,KVbK]Od</xp#R8S[3cVvFfv?Tfu_3Y<Y1;Z`g,L;X/nVh2.7>Oi)[eN^hf^)m%uKP+u+H2#W8SQ)5e%kt.5$a0*OO.)H)UR5s*0<5)1CiK", &
        "DEQi93-E+I*bFjpa=0+?KYv3(]6hcb)1uiMrZ>gbDlX-+(k95gO^nrRR>C)MOY.@n%j>,3A^Px1qPvC$pk8$gD>8YH6;TSz;pO4Y,eWhG`Xb0E:SSzpN#q", &
        ";Q@Smcn*]gKGAidJD4?/Es8xY);P#^MoQ<tp<%;5c-wEaMc<2I/mi%ha@oUw#dnMsEmsK6Iq/JS]k^e<mqeO@bR>aN.Z8HM_Uj)2]U0]H#-Sn[N]=._Eld", &
        "%g2tR=WycRD[Ib_[e>Z4aS?ZdSQd1_00J0T0G3M2V`QZocG2V_lS6@P/J?c]=V-3q=foAZI3;1)m1g$.QZUA%yK,51UJ8`dov%`>$1W0>0nhG8fQTfV4$B", &
        "z^nG=^<n-k,6q4]Ze6Epo6Qgx-9Cx4ps*rN5A9jbVS6GM6pR2lPhiwh7/c#`H$WlGBW8N$x5sJ)4E8Yj;e0aa.1lLK2]@JJf%nQ@b8e7gqk8ale-5a9yHU", &
        "4/A7*K_xTDce?dn4cN#M>B]#.]o-$(lN5TBaP;8q/5wRP@>:RbL%<lI[t[H<XwxP5Bn^+FIkn4l<)j0,A0_%xPUTNx9:l9=J4#5:Cw)*lKCZw(q72:xp_3", &
        "PnP:v(D,ByNiZ70,s-hz-`PT=?[ZY1>YQ*?X9-@=EEP<[4zhD/<HT1VqeXj2j9uWu9I:3*>UhP3Cp%j]e%o9S7L()KBBCsAunq?*_DPUcYz[^5Gms6U9:x", &
        "K4DTJR:IvX4Xa/$;Db)B0.3=:0`f9e)JGnJnm*l`Fo1ke^yS3OmyV0Kuiw#nn;SQ8+YZv@scq[_Q71Sot*PE3?Hcc`aOp5tpHnmGr:4TJ%uMJ%SsCenb=u", &
        "3I-8@^X3+%@I/)wofnU4aNwQFbT=__0-?,u`I*dSsVz*u^fq(^4yC^3huO:4mJW.RZ3-lHzUD1)R8w0sTQw@59;NvpqzCB)OyoqiV4Sl/%WGrJIqlj+>p2", &
        "I`HRylqHYHv0%SO%6a,P;?6=rb0VHm2WAZdA+`GX[,uU+^f=?<rVB6Sf[^Z/47=du2C=cWJE1hRz%yVADkhq;k$mA/uV;FiZ2Tup4I`+b.wCAzg.GWng7v", &
        "ar+IUMg@rIxO?.=.Wl%3Jvg_fV8+(/MFNkpWQP8?;N=IZd0Ww5_2_>DY5-nU-?-JVpSWNNv8$B<YYC7*5Pz2v,bI6-Ao:w=@0/3]Jxp*[;3ww*EF[64LQ/", &
        "Scav`N^d+aXj@q@B+eqe*EH.Z>pB$B7zjYhBwyLwDSHc:^gO(yjvOSk/E^A=Ow9cxj=sLWp<ov83s5`ea698NnRT,Ln:sTd)K*EmaZnwjPom8IQ$m6QA^R", &
        "Xa+G+pa<N;H-dE2+s5%d.:I#WyL)$Q1ta(UKVMliX^MEEn^9vlPqrVDph^wWm8F%q;tfzXcJvV3DwR``?gsRS:m*v/A6<w^kLt/8ck79wvy<.8>oRVB-9c", &
        "O<o9M/l)=[p@.9[r+gf+je3[tS:LlpytW_9)^+<vku.%Vr25>`Cwo6H,S>NkE7]rhgcdW8g@Iwd[0eXq4`.r9Qj>8@Xx@]AEkz;7;4oauU>9JZpqf5o.^a", &
        "2s,(z^mHV7:+SHP,q0zw:iUGB$Sfggi<vPPEtJ/)VXtF=;fji/YpHyCo_;S<8:iUsokjbzqvmDD#kGThqX2Hd0k08-NpSX9$`NHGtrIA`$P[mjUK[XQ)8l", &
        "JW9Y.1^yPZv;+rn[?*pQYV;g^lGBc>ydbSfa)V?Z=Dr2M61wqz*;2StC/Sqsiu,=QzQE*D.IN.7?6F@aob1:>=^1FFf+kfi_JZYy5Ohn.?F(pjUxK/pa.0", &
        "M0MItaGO.wV-KZsg`e^jZTR$-.hI(x/ccpx4(OBJm9?%hv46aoEScW-?u1d8V$tw6MI#PVG(IrTXFC=-f%w7Ls`D%yrQS%mD$RZ>on2UJ:ZFj#=3,Q?9sW", &
        "egSZ.PtV4XG?V:+Kk8(zRFCrJ)z7)r#KPrE4:.wmxkLqk#xp4Q$:=5B(V#8j)=7*PEyJ*Tg10Y)fCCchlJBS;doePu$m#gS[-]RHgEt7uIpl*kK9K.`XrD", &
        "4P>Y2Q0zrHXK>+m`*dB_9j)H5yrIB9t+`V06CrUsfw*B6IDQNcz@=QG3R5t;e5Zr,k9-^44zx(EHS_7lg=^HO(JtM.(X.OI^/d%C7=[OP?Wd/E`YcCg`yC", &
        "aef)w0#R=Uf^Z?2D*k(VxVW@PO2z3umZbsyB*,qa#X%/npRucpT+*;e1<^RM1<S0v+e+tzJ1q#[q:.-bXeP@A85^R+DZEY%kn$x[(iHO[vHAPK`OI3RAP,", &
        "pY+I3?07Xt_UiOe+g@585e3AR9_U#C@o@a`LNer2YU6mf3DtZRrT,m^b):gb^XH*r32o0gzfLAxmErqpgnR)+t_K<0cE^[gf#ZUz?#pnOnLFnfI=YLaTq-", &
        "Yc;/MPs(Jo)e^,L+.y2?-=fB#?pz,=OROFi[xDZLnI8em)F([r*-iYMlnflx>gj,w^byHW%HlM]*B?`qQPx8)_ZCJAY/Xs@jFtv-lcgdOo6=vkRSLn9eK_", &
        "4k33XUQr$%+Ie3FhF.moX8CXF-uXk+-V,wn6^u%yeY4sy#/npeW<3?uAl96X[m0`<)%iqUGmp3ztKi5][HPwYY6%p#n8O=??9P$MRedMd,0F8rhWL22jc/", &
        "lG#M-5n7+dax7S?5UjLV(_efO.k>=7Z#`z+FG>,Rowo`PkCDiK(DJe?X@90k_$Usw4ilQAcO3]ND-V##D[nZ`do,;]:%DxeX:u_Qz^TcgZ;7QUQTMm+C7;", &
        "gYZ8F4ec)<20KA/B<I0,44rVT.%#h=rR2Eas^YprZ(II[Z-#0AUd5?oaDByXOTxGUlDLv^,83_;h]T)=E.c,AwRC.g:f+Z1;VEqs2k,9j3DMX25pRQ5.x1", &
        ":gOGhFc9Fl3j75)=U^dQ4eqp9zRbe5Z_:)Tf^DL92<(0<46SCwZ+h>82b:Od^qwdf6a)OK^Qusj;[@s^*19(-(`C5JW-M`FIEVSG*6wGG%d=61K-58gckj", &
        "[`:8`%Hfxf(ywK1;O^+nDYJc$(rys.pO%gw>UY4C7tV4d/s8R+kwa=Fok$IqqTe015A^i3dMzmnsutk`(?ZAlPG^Tw]6xAg:s>2qSmi:;?FQ,hUZFKm2_)", &
        "GjnX[(*KlQ:f;QLjt7J@`@^VHo1XZ(fkn(A1aIhG)f%>oKq)z79=gEUuh,D7o@r(Gp;9,GqG4L0`I-_uFu3Sb3.+-EcGoVHfP+b>`@muQiBKGHDwo^L1D0", &
        "@j=)w/xlhW;t#7_0;g-VvI>rh^y-5tLFrnF7GHZMEYQ_I*f%y]D]bb40n8w>d/aj>XL9.ZFIpj4vlhw*yX<c;Q_<a-bx(8(x9I(Ic;s./x+CnP1sH^@M/0", &
        "T=6UQiYV.wY%WYA%ddM4x2L-KhdAa81a<q.?BJ)pcfHRH6dCcTx8YBf5UtLr$,j22<pB*o*>Gy2e;L=gF$3$$S)mnQXt/?;,H0aLfgI)I2#B(IwTK#eZF-", &
        "[yf9mah42XK0`sPvQ*-[Tx,fYI1OZ*BO[%Hs=?Kf/e7GU7Au4*<Uf-wf$deBa.6v__fXp[xcVniPMA0q0drE]`IWtOqz@lqWtA(*huw(w#V45V[sU.AY/S", &
        "]o(4@^4g9G)5wfEFSZ,rX;*Gfkh%35q5gjQBAGHvHb8RTO.rEuK,=@-cOMN,`YE]uFP+Zd$tNt==mr>fdAI3<L(<tF18X]?w.1cUoUj#3,51RbS#O3Kcs^", &
        "JWopLmzMVYR@_-1meDsuCzhGP4z<5nB.pbXXYGU4B6JVq[Zu3NN$mHIiM<zUi2E4:vqJin1@18>s/:qya7Kb#wHBfjl)UG+F_jH;;g)_T%Ih-=BS?@ExT.", &
        "emb*;U*5NbO0U3/4fy8j,c]mL5C^bPFmvCF=l.5OLW)8,K]:1n+@9]5v>#3)HS3.5n32:vy4itsf6.GPRjJYMj/+H)i3Ms9?5R#i1i=?9AC+nXZfo@LPpK", &
        "zMr3asMQ<C0X3MVs4q=^/gq(tX,alFGSXUXYNlCUQo1+mX-C]IKTK[LB]AYa*ciC#*JK4lndiqvxemv2BcqMDa+8(g>)l,7<qtOgvG5uAXhHqc]9(gLj*?", &
        "f#5/Vrt4]T4MrVddV16/3OdJjy7:-OT:W1l^r]Q2k3ulinZ%2,ceM-XA%+AL>=z2+9yGOJ5Nw%rn@bKDb2);ZPAjFFlP*qoLQBr5C:Wk1-o84KxQq[Qi)4", &
        "^O+fzfo3ULPS#LyJj,;f6$Nrshe;D79/[;v*9w?kqq_Q`?5[RlI1JB7^e/7`v+3UW8T,xgr?Z?(-qo(xw/HUhRN4U><4DJ;W7Qe;jMK8md7[2%XP;tQ/7=", &
        "(q*?5C;d*AKe7zx1#;2:er%,Z)RfC6Y_u9WBXnXi_p#?<9k>T:T1gGg;3N*Od[<fsh/X;PT>=Is;Iw#AZVud:NxcpGz%jMe9*8y([+L)/:T9k1szXTKCK@", &
        "p-OK+h96M),6Y/o-@[0VM+Dg`nA6Mr.F=jOxtd3Hj<k#_Vxgh_XG%TOLW.whb5r.wY?+Aru?sIOg^L=,N9%0n8+P=Y@r1t]*k87,FYAvAuu(EG@4_k2T_%", &
        "yTW?uye,Zou#j+c`n$3Fj5?ktJVwp8p[a]L[.Y[HI5+VA3.A#le;mgFGQtXfqA2Jf^)C9S+u9B@XJ/`f=^FTF8n$6zRv=`/B3<.3Vm<89bj2DD2WMKUHAC", &
        "mXo)]Fx5ssg+IcJ-Sj9yYqf`=lnLQ*ivi)_v>@V)zocC)4Fa`R?V9D;i34%k*HFW8Jg*hye]vYaSgO1l7U94Lx@<e2>24Ic8%$^Q`WsvC8=zK]SpGhL-I+", &
        "Nm*n%uvXB;fSlT7pq<[aFNKdw7*>x1U56r*GY*M1<pa-T%,,VgJ?B8#U1h_Ojrhc/429<(SG4HHe]q7(2gAdjEP+e#AAPGW:Jc-z#zRlAwci7wm2P$>akI", &
        "AAuG<zBZlWkxF3QK,Dz`r4W3HNcg-kV4%b^9GT%AU%AQP/UU>Tb]CXZB0u)0pMK1B7@%s7zIfLFqYHV+$4,z`U<32e(.`l+m]okheQ$.6V%gBZ3qD>Wkvt", &
        "2hCP`nZp$5JD3s5JOPXtJc`$e20YFaj+/O7<oTLnC>#EZ`[vb#Soju*kS^5W[^@B4Y>Gf/(K[u*%$K5*aww;_;1FgwqeBuRGn`>KAV9kPeZM47B)0XD0p.", &
        "1PyP^0$X7j#AZ?WQIC%:ANsj2b7a*],PHFnS:;e=)+U1q+cz.59:Vlk>iWAATp%BvpEqMvCvFTH1qaPbq5I;PB;_iF/V:2NAcq_YvKwu.@fL9XRPk/iRfJ", &
        "T5O^o+H;gTmv[)y=vAZ8[QnH2ZJgAz*@sIcTBS$1E4q.%WfO0@sNRsm62$t2hAzsg?^nX1,C9EL[n,X?7DaN6j8.Zg)EA=VTG]sc:FYK^[IEqMUKfHqXSj", &
        "+X%>OWH:2?4m.7*.4?G>RhOG-tQ`i(Lf:(bP%j(LHtAHrMQeaOetV)CDyM2EP%j1bd.<6$loL5;MnOA/X1U$Ace*Y?Pi,B+It+-r``ck_sJ0M/ELF#J<b]", &
        "4Dk`kH0MPurCe.q*Oor6D7HwFEdJl)/6AUO<ES6l/4LSQ%2%5l:kf3,zv6*(us74txLl2UnBmg3GkDgKM4i4wo%0U?>4Kol5g=U8LrMOttZfFu.?j.N%DJ", &
        "km;.+<IwR:`V]bCoBBet9=#bsTQQ0,h7Px97Pgw4Dtn[vcR//2lj,($2bTQx+5zi,n9y;5nh1AkaocSvyR-p<KiO%vxaPQk8jem,FLeZ,t7iT;k,)H6zh`", &
        "+%;YMUKh;M^72-pX=6TXwQ)^>F0qHx_S<,MY<^5FmfN<<*S_X$i4TFZWKD5reoNlUuW@K(TL`Ou`nzWq-RbSWh..dc0XzE7USk,0NOQ9:zP92%`iYWkA7?", &
        "oU>Ep;WgO15nz#[#8%f<WGUp)$5E.3_M`IT`dGs;/:f33,z;78RyZ@Mme6LFhNcc5N$BNO,re*m8=3oLHC^#@Ttd-NDL7s+5]Nw]AZqMZogFVu*R[l@JNq", &
        "#bU:*<`xX3j??#_bAqgOsKgC[iyr7*MHZ=5q^H>@9u?@Me3UPWfjUyIll>X9DQ3*6/?A?8r3k`dd`2Q3Ff8+_9H/a[1Z/h2Q/[:DOtjlS:si8m.68P)vfr", &
        "G*8XPC)^:FYOcOC;96HG6Jth-9H3wFtM7[H-oewvQI^YB=6IQ6FlrnhxbSp-L>It`*T,IYoo.2$.QcJu7<I+AG?wkd?j*:,`NO0gDDbdM+Ae`:t]$WfkuP", &
        "pJQR-DfRL==[%u.y8OLAixWnXO]x9F8z%V)$Rb2pA@#JAG_CV5(2FCowb2ntR,-2Ui7BZUzsdgK4KHcE.,AiOLG+<5.N_+1]d*k*uNLr#N#Ogl^M`q^3cr", &
        "GKQj*Fhf4%NX8_p%Q(m#J(ZsBD)AUEoN#;]kJ5V7qSkwG33Kzp%cqZH.lrP2`IO[pXbQu:_cjkJDIExSW$oa^VCn54=$.;tx;oo-3Pk?(`G2Qd_2<p7zpA", &
        ":#S<%A:xR_rG$hUjDvOaR-joT4t%[g;/2nx?iWVTA(xP[8a57cA2v01cn]9a7MEtK[<r:e(u@=S^C8MuAhwLz`t-5<mxLR(//qv0Ca`41jjzLnbS+,Tg8%", &
        "h7^0D(GgghPf<bSrC;`%+kdmg1,,v(H=MNz1:(vNQH5z9%+99Q1^fN0TBRH)(6D$k`);I-NH]NV-%z#*Rd+nn<MI>>YnG]-g?97#Z8v$2<A?d3d8=0AKdf", &
        "VJ.___nO+W$X*.GRi;#f+osgDIfjPM)?`RRZy-YpdZS_ON`BZuZJk4g4IUuZf:K/y-s5w9h+3@814_-hD51SUSe8F)5[/LCU-W,`wXR7p_%=p_W+spj;U1", &
        "v$e1%Nh0<`%%y6*[.t;%Xz6Eq/r]9eSlNnqtF6#M;w[on_64fPpEMF)MH013@muqvlt9v@*6r]Dy`6wR-0`/;R_UN3MmyY>24l_Cn(e0?vSg95%>/jdU3d", &
        "9PaTyv0PE]h0l;.;:=V)CL*,.EKrKn:Db=[e3Qi8DAGX/hZ/B*93BO)+(Ep=Cr[kK(EM>+e4Z+Z,g=kNe2rv^sJvLIZ3kz<Ml4O8oZA@fjT:gL7]sG,a?V", &
        "sRL<;g>ko];wNehVrBZt#A0S)xpgoF7H`)HEk;4.,*G=K^Zv3/Td^W-#tfrUeQ%9+;`4;cIf.*B7KoE5Op6o#*u0+3E9REq4,tVq<X3`u:uJoro1U>9mn-", &
        "L?NTe;:+;H$?q8_2vRcsQryRhNJ=8`71cG(uqX7;lex2*PFh,n/0yru4>]hV;nZVHKj;qS4Q;%H6$6+MO%a?m=x=eB.N,cW;1=bN+J$TTFPZ1nF<:ff@kX", &
        "hGO0F]6*>]r(i)3=]%y%MPZWEB/Jjz/dUEEz4iA,:/kT+ZttK_HSVR7yz7hsxY%gxW8Rm?G2@QUK3M4CJ6Z:UGt*5/5oCzLO/)Pq0)s^,pPO8F-UrFwHaB", &
        "@,.Agd^[rLGz%X,+v%`+xU81[C)=eY*T4cKDD9_OBU<DdaQ6Ef>8jwUE$%+7-tQb10L-j+EQ<f05s;S$h*HV@3UVv*mZXZD0Tr,>1t^HPKMB5^`Q::fR5I", &
        ">ujy,R<g;n[TR?S:eg?iPAK4(Jf[];KT<X3RNyFB)d=Kl]dA7)wZCM9QA*+u#.D,4MGRhya3Ssx,EL2^zq11d@+.xY9*6@mCXud[jHX=5qHqwb`I-S9(Uu", &
        "yc^I<zdn6zQek,.>a^B`WfEk#uO*wHKwdqyt+0<DEVg9n2B4U6.rA,jsiaj?Wh$6Sk1i-2Ia+-%%i]$b;<<smGk,9+JNQDl:01uh,yX>?4SIW4>NeI44*B", &
        "5KxJyIgP3AcR->L^aLTwBs_H$*.:^AP;GGV#EBC+#TklTqou3VJ?X<M[ks[L0.S4yN3*2l5jx#d>04)@r)HJ*$).DyN_9YaYNuug0I>RmRz=wpE0*:+eEc", &
        "D4o,y19K]Z^q41-<^6_Vr85/1XPgbE*6#xysy?;0K=eGV2<sLj-R+zg:Ms[8uWDQ_zh>cm%q<ytXNnew*wnQ/$jF1b699NhdW2ss5ERKzNiBS3(EeL$r6S", &
        "S4(+`.$Ff9]`B_XaF$:$L`fqA[l*MAjE%#O+_eJ2P_HFXU(tBSn7yUSqr5:?/Z<P$v6g<jJ.JXFV8Ge4b_]S=u>:eCx2ve]O>Ap%7R=]RHMHlgK)]pIU=6", &
        "^v$4%NnmVa$Il3P0S^I7rh@5i=Gw66=*;]?mkP:dXsMDBTJEMi+0wH6UUsWZL<m[ZO:t`Q._zWx#Wo7XPBC[AF:;RS_#L[id>y0qJ%;Glh?SpFLYPh9ev^", &
        "Q90;toQe.<L+X2ULk#aWwGB:^7jSG)?tWRhKx_+pmlPoBC_Zv#fk;QD)F;>w*WL(1Y9F*f^uZ;(<UGV8(A@3iHtxiVm?85eyBz#Pn2*FwIfPO7X0#:>%>_", &
        ",p?22Nk^)f6>.Dv+VDlII#ht0LnhN9PdenN>F5odVr[.82x9t%L)D6P;Tf7DOAt#7nPr004PaSVXsbR%>DBCq9D<`Po^hqrekBOHKrG/yKC>S/<*`Yp?4f", &
        "(4AF(k58P)uDFP4bRSdB2hH>@I^:7P^`V>ih-0+(ZM6E9]V7Ta.^a65X)Cddc[qgpbK)VgRcLzSFBLOVK>v)lxvw32@/OQ,.g0oioMk4t,tf_c-r=60y$*", &
        "67g2JA<-k(FuVMo^nS>AE$3yR`L5a2-YtsKZb2<o)#1jOnEOnfr@y@hP*Cf?HC@qD[9u:1S%?dQ_w)H2zd0<-JDAk+%`.YR?H(>wA#u)d6;:=79q5wG*HE", &
        "O>_H^+9:qFl>7r>:?jn3^*Zi5(:F(pD,vjuykKMocDOYBhYn<yxT8S8;=M`wGfGW_jhd?hv6y[#+KXsCyQ`pK`du=#/.oho+D6>ebJzZ*V;:hSfN8Gb>GL", &
        "AK1>w9t;OR*k<VW7z$7[GB4h>BlpoK1UD:c/B,d=.-,7>b])?aK>nlo5D%c6lfFJH[t7-CAmam?XoD+Bg@9_iJZg4f.PIS1-Qy,fmH)hxg?3iN+q26Os,F", &
        "EIIq]p=;RP*ly(CNuaG^D/t:rWEizM^l,*j?E$$o7F4?r6rp:gR@5:XkWIH,q<Y[#wKSr`_z[3r:.L+FC)0B)>$`/FPp@e*HD(qvEEo]5*;LMP=U@:,Pdg", &
        ">QXf9BrU#]@H[DWk4Q(84eiv.$<R^^7r.b:8P%Vpy@*pYbsJZqg%HzQ*5N4L:SU;.-5>FUamk_/VU]REJM/B/AF8A]io6vfB70Y=,B[y@<8n)4l#RTL+Ye", &
        "JtpssRcSj]F%rL$e5LA?D%ZtoCfHyUG7FFule=hQ.wjyYz9b?hDy(g7-I#Z$UIp1fKxXx<I,7qf$w=iS@R]s,@:Nr%z`o_;,1lMv-ll];A-0c;v-YR]MKc", &
        "7([2ie21*2bZk;Nq8,*TH5`t,Ahg]Z+/@<cH[%G9HX@NtcU?.5.R6)5`eUe2]@B(=j7GMr`748#).+vU6Y0#F%IufBeqzRC*NZJS`qz.,@*jLBd;ope%`p", &
        "M5o:/k15Jz/>COmj@9?*=>iMxVy7Y$hZjnXygYCWhY.JUsj8`xvf@E)Fpc<$V1.+_Y2A>U+`_1Zt>)fwdC(T-C#,TY-v?;<hdo?GVP3<@UEB+^2(dd5SSY", &
        "J#-vd;V5Nzj_@e7(;c)^-+vc=e5^4^QYDQ+$_>+<52(plE?7_U>`tml#n#*8%#pxjexj+,Zau^D@-a9We*B5#ieeZc:YU(S5DNjF,5@Qb$,yjmCAX+(5n;", &
        "A$Z7ImEUE8h<EdyXh2Az$;)AQxyL,S?<]R;;JPejWN[(YW9wz0cM[*5pCFO:ZLiE,OPBvHaN5uk6XDpVM]Sd/tY/C$ED14FUVZV)No+/iIJqZP:zcb(,GO", &
        "6C9uHYCPuu3+:[Aw]m+U`>>-_RW6]-eqMbt0nVm(,rOB#j0bkalJ_<.dp`I1_UmYi-I;H*ARCdst%PQH%DUSwil8;w@/np=8Fc;Td$Z=vEKmf%b_yr9JQ1", &
        "d[P^e?-$F<CdkVl53=KZ(@akjxrEqYsCzWHV:.Qz]<:j>8fCBwY;q:9qWsHq$]-Q0Vu>,`vIz<qlT:D;c:cOY*i3f:+0^i9a%S4N=nWm[WeV)sR<6`_a_z", &
        ",eU_NP0qB^*LeKIwEo/VX:?7%dRc3*uhtHsIt;10Duu-Y-#`1@%e3T,diV4PNBqb/Fz;))c6_s`^nWcWTb/BhB6j,wE_pgX;=/Pp=%`,q#?gVuOP]=W1KL", &
        "EUl^nsZq01OLv0*kei.?jdS.]+;0$cwYghm81y96+<FYmD;Hx8$K(8HdNQ2YNnAqccxIFa4u]+Z(TXDYO.^0WtCkexMQ[`^moy3QQ$E3D;3ixhoF)uKq/d", &
        "j/uwG5Ns:FDEMTRXFs.uYg:TuVHd5P4=NOoK7-t6Tz6g,J:LP=G</Vz2?M$^^<Z^*]Y?7Puxnd=x^p-17WM*yAxNht1zR#kfKd2pKgSemOPn23I^YP#=%K", &
        "7qz.KlRha:;lyqLB]$jff`hB1EZQC;=1)%pL>RFv$;@::O+N1?BJ#+^3j:yAIBY=a.xoz#6;N+E,.)wU@ZdmCVT;%*MxUs8i7lU0tGjznd?adLqxNbe9az", &
        "H]sFSb3F>at:ZO3=<#*Af:c)[_N<`hl/>O$:6D:-)1A>giUv)xM,p*?U7*_jSu+XRSbXZTtikVXU=[:]oOImNe<lM1p(7Il-lprKmnTq2.Z_ni)MzOxLd]", &
        "_2,aA=(l#dTNIf4sCS<<x>v)wli_jgq^?+QPv;7,<I?HM7u0L/e#gYbdyov`zEPqzK$dPePqe=/>#)l68A0mYDw@%=zT.7B>-i%R4W*OY53?(y:lae>g1l"]

    character(len=118), parameter :: BLOB_ROWS_10(100) = [character(len=118) :: &
        "SXp=./C56tt^`V9?7SXQ=X=IcfbCkI$>;_z1O0DY,OQAq._dr4?mnTbYK_8<#x%$-=(P$`)g-2Hp<wZE9s8p?[snFcm]m]5ZTs83B6oe?BdA@0-8x]^(rp", &
        "zRO2VE)tVOfDE#?Wf/h3<0nu;3.?wGZ*$U,FJ.7N_if6_tKIRa3qVPwMGFP6uDg;Jnrg$dLne5v.z)Lc`S-J<DH4<RY:_BsSU%izu?R*n@(qZBD^[P>/u`", &
        "6^=WaMirm+fBC$dQc-X+9fr``LueU(q*1gfTaI=GCZ^:NrPYwAH[$?Ary;`rEK<g55>^_Go7qr)47OWRaQ1@w>bM]OJ2R5^jhY,PWX8VX=yT8X<Sk;x6@D", &
        "eR?9R8X%ujeb<C@p](#]vv=jz]eJ;)/AXtq58X*#4Ar4knW47`0dmk#[(4-bmlvO?+2)hJv*uT-`N^)LM;2ltCsf,rF)cb2xX*@dG(FCHJdj-6H.F-Y<Pf", &
        "_FhS<QP.SlJ=JS]GvX`[)nPL<OhxVNFY#v#,tfIKvd0Ut:m+rM,Rar8F.s.tZQjakak<H*myV$xF,>T;2dGqC(F1YIPO4k]UUv6VZs-Asq0Wi;u3sR*ack", &
        "B3x05P6FdsPKTM=PPhawii3q]OIZ7#s:hM(Wo52hO1G3d7MoN*[H<kq*Hm#@fE_WheV0:lSVAK2>lhS,Z_lGD;P`cY^5t^1,^Zf--DX>ka4(b4qAuvlDo0", &
        "QT:o*Kmb)%+iXPYOUJ1SYeNA@xCPT,LF>q`5%ZZE6Do5;XS/P)YuIVYdTAUobmRPM2))q@sts5LZdq*nl3Q,ox#Cgq>^sBJ3N#yAu+DlE0kI],fG[$E=-q", &
        "UHAWQQXle=JZ5)Ig]fv9lR-pbQ-hQWqD3x_,TtP@#>b*PDo^:):J<k@3@w8p#*9BkgsztJY[O%gZ$C]2b8$]3x0cG1V_@yNbpVZ],O*Pk-fC[,Y/k76DY>", &
        "iOF)?^iYcMYJkkT@_vpeCPi[dSWfmc_[$$xg[%Jjg0#+`:AC(tN8[$916Rti?%;4pd7kN=S#L:iJULsLmmV,5g6wV#_5_tusTnph?qeSg*@/CFZrF@h?(%", &
        "sHJ_79/mC?*?p?#??X$[`AytG9#xLV)Q<,9q.9Fd?z/9I@v[3aChSSwO#_R/+Vu,#^dSsbad?KYX6Fld/nJsY:x`#+n[6X/JSSSWvY,2A8#q#59WurZdpK", &
        "b9cyhw5=N[I(P`>_7,]IH9QkE/E8dwcHf[IKfsZQ*cG2sM^7--,ugoB5f;3:T$2g$iAV@JM]Z6NI@vl:**x+#:>U(0pa3xf9;-tjW5KyAjhejXo(C9pHJc", &
        "Dq+CkI#R`^vet>2zfH@AU(F*rWeKJIAw_rCzRierDq*ZK:uY)]/F6qVl79]9r2UugTHCxJevi.(#)B$@0^lC./pkRbG[dt1ca[f[Bv6ar*AAJa314/nOwt", &
        "z;)K)vbKte-GC?rNK`(d[t+g%H*U)ahc?<.gp;WkSxfvl]q=ZT@9Jc^O)m)*V6T6::N:3kVTob`N$j8DO<`.%Ec..^aDe04A(<80:uZt$B%?bUufXE0HKK", &
        "@Ft;V<<?iPsR5o?+Z;V7ST<4I//rS%+rdp8EGgtq6`*>7]ddT>9?[.CU2m;,EYvznmu.h5#8#;7Z,i^wr,m,$$_PGGtP3)n(/A;S/tM*3w$6RYJ3_ZCpOX", &
        "Lmi.$UL:<)At4Od0$uKV78k-Ybk?>)d0=6<:Dbkp?TV^l8qml^sWDGV.H)M@gUxDQ,NVh5@;t*B+F+/)m<y`,TJu96:GSn;K]%?,aJL1VkDu;5teq$%91^", &
        "RNw21n:U>[iRMWu%q6dx:BWBgcy1c5H5$1SDbo8aAKXbm,GU(14S%3$*QiA090*?nx5sdl#cw0@TZ<*/4w9$)h9=^?#^[cqP9F8d[TM^i`Vq08El1h2q`k", &
        "<q-v*oM,w*tVI,TkYd+-h+]DE?--ukB-3k;KCAvr(O,eQnS-G;.KhJ%`S[<d+Y-f[;yd>Q:?SVvS>Mny-,OaBBc`QnW/i_3pA4v69IBV8SxE:Y8)UL5^[B", &
        "XxlrLqJ<P.mcVw(T(0K3p7.0urO*.,H5+zYdAWgR_[-E)5_Qjs=M7?MRPwuwJDaFn<3bNS,T5>1BG;8lqvQwAG#lmFE2m`_N$3wIG`6ow%:z2d4Js2,fW;", &
        "AT5]W;iOoeBulRPZVG8-nb5GSkB>lFLI4-M@6F0CrDEVhx]eq%UKd^HQ^f:WBiZOlwQfAf<0FxhqSn+NoFk9=-bzaozh]3pa%bOI.sEIpp63FdLP9I2c``", &
        "M4>kh[RCI*Ppbb55GhlGC4ksMBHeV#loHk0N0JGVUn)8lVCyUokYP_X^`3`Sn=:es0]%*:mEL4dT4:lGCWZYmiCBUEB#8-dGWiYQM9VPIId6G^1:[GYm[H", &
        "Q:TG=VO,:2H-?bZU.EbIlqNe$(^WvBUUtgeGe:(/:/*tqEua8AGl*IORRdXPc)FteBb%.c^)^:4u@@K<-Ddr)^E%qc;eZFTv<z%Gw4*Nch4%z;_b8g+ebW", &
        "0%R?UP$nuTI:nlt>2FU@ghaD`agPCKFDL/R(V5nao)Kma5kv8Dcxr@n;@?v`7w5d-N-k08(p*HzNYd@12Y,dC2eFA)0/t1_C,uTu8yef5G`=:Mn/>0V)7,", &
        "pI2F<ac2T?@i8dezOOj3m_`q-1f:/-^+?YKn1RVE+oDx%HuuL%o<3T#^cT]Q5J<qViH*$YQQulMJHR=q-W/4Gh$pDRS;)611A3t(o)MK9eOZC^v3+=25zi", &
        "d6g^2rD1EV-mF[J.2)(KI`Xr4r9:B4te*l6702S/)L;%<@.#kC`u+13V5eN]za2K=i37S](=x?D-OQV5(.[?5P4e7.m+q>G$5hyYeStyaFR%dz]kKJBA0V", &
        "A9w,r_6RW5kLU.ZuD*w[V_sa:I+^1,kqF%%I<0$gYgJ.FyPv))n8s7ypoRUgebd6xGF(`0X(2u_YVrDKBQ:uiS`*s?%v)_NnfOs.*KbY(L>3uiARz._1uF", &
        "w]F<Z#tZbMugRzteb6_OqbtIEduPA?6myo]OxYSms?(OenB+9edr,hm7N]B9Q;..ms?=da*j5Mh8>?ESAC>rC.J>L6m<XVajgPh8ZE*5Rd,zHnJv(V-s3+", &
        "b6C65WL4b>=v(zZ$7lz4XVsBW*5PTsTE-NWt*wHE4pY??su*?+OXtJfzRZ%MmJV1q6vU)voPPU,/=?<bCyGb#((RkL[P7^@OP8HKG,5ri@3e_z0UQo_xm%", &
        "u:+zw4Hk*Sty[q1^RIWSty[X1^RIdN4;`Et(V:w>[`7+3Iw*e3H9lN@4379R+L$u4iM$c:Se`?#D2sg,:)J*._Jr?nizC+^^V.-%vdquM]-vc*69Q8oUJC", &
        "NpqQt%5dC>8%?qzFnn55W3mukhmB.#X]>jn^-@4$22`]5ZAU9t*WG3ZU/y,*J`ds7bHaZ0($Z-jTTDte-a7W3^oiWmml6[F$_7QDEVvGSnPRru;B>bsT4s", &
        "SqiR36tnMURz,gIA)uAX5d4]vSu$L+#)cUl=iyx4t.Ijmt[p6L@8L>9[S<O$rQ-na?USe-2p?]y(.gms6D29Fox^M%F6QW>6]u$X5s8L:wStW9-*;56s[M", &
        ".a$jHN:><VE(H(8DV1UEXj)KLY_FG#[ZE3@+EHW.p-Y0k$S*5tn/vau8>D[O.k9EyF/u/=p-JCtPH=@Qul+KeI7T>JF62POnpY/2,,i<)AZ^O1*hg8)n?C", &
        ")fN4s$vW9?6A4GYtb>[4T,Mz*aS*W/l0S/6Ev#[QXq-$j[d7El^*.AS.d(PeDb>^NB,nFQ%Rn5MF<JDbu@9=vsFPT1BR7CA3PBp>bIN$z#oChgs;MN#,`M", &
        "RNKSwcw$YMs1?E-]JgX_Qr$<KFA`^N7Kyf*0=@V%V6zP%AvEws4om8NM4avNZ<WA#r3vt))Xhb/s2R]XBamt6aPuNqRE#W;wI8t(Vpx<w<FQ5Vd-Tng:y(", &
        "OkP-Tih/OWEH2ph9axlnmqOqK06?P_n#[wBK8n]Eg=1$/-1uCpCggJqPpZZi.qqtUdfpK$,.z2n1=rfCpAVq+0kjxTzPk31)<R-W))O=-5X*[$nMsQ1*2b", &
        "s-pv34qW4?HS^6]uN9BbQUS3N#V?-.SW(Cudc#vR2v<)xU%.*FO87LrT%z(i5<s-9]fv5h)NTe/kOVFr=suY)%ng1fZH9%_x<8?EOm?rjJ]G-)Yvqnns2=", &
        ",2ug$vE%[)vu@)4_3U>lKxQ><w]DAi:[n0b(px0[8:X>Q7c,`l0W*z4jM_la7_DG*uAF;oM-bnlgj0CE0X^%JD=oQ3T_,S2^BRw15h3e,4R()g8,wdq$Z5", &
        "rcM3C*MYf)kEBv<@7nbZoCsXpwapiM?=6[?#9h_p;R6?Q2O*GMeKJ(R$/d7Xp-%z,]uaY`7SsLe@`4x,G@/cFlN9tn;XNZ>GdDw3p+sL:^>]=R2PfCG@]Y", &
        "/`0J(l7Ku^bnSH1GQATWJ5fF:O0.8SS3eEPMcd7OsI;S/eVr^HW2KEI;taH^]1QG-)QIFPy,N`kLcj%58L[_HVjHb[5pZ4pJ?kVk,O5h1rAnGJNv:EY`nl", &
        "8cpHUDnci;Ipl$/[tSDthqMu/s(3iJbcpH_-Ct2>Gcm#Gbn+E/f2<Nn_O?Yoy+FQGa1iP(E9m%)_$AQwF+lnb4;]=M3Tm:H>7idWFheW-sX9@9z8fAe*A/", &
        "/OPKPhXtMQ6ZzarU1Q--5ctdGwk0vOk]=x3YYUCp@WnI%=2^+<8KgYTzU/9tR8zE$SK,/`2>f9^U8rQ<u@jP4>(r$?<82$Z.`m?Y>9Y+JFv3W>RoTCt#/.", &
        "+0n_iIl[2aB=(8yLvvMhGi@]0iK*SD2H0/T=fN3[%HN)+ioad.(2,X.<veo`K*`hKOzQh.f>T4>eTM+c4TtN*EN$QDut>*?*HO`]eXJDB_`A+G#9W]]u=b", &
        "$yNFHi1@^Mxjf5tP;0*.>KjLK,X?9LXY7pME,sEA6T;h]mUK`kYL-SRJ$IEIBwOe$mM+WuZ(A9wlU`Jw<0vB;V,I%HG1QWf*d7?@6RE9/mJ-TI[+G0Hpb%", &
        "CTSPMQh@v[<-v6>GPNJ$*kIO]xV#Z>sR[J0.@BEGEdGUu>I=%A-[evncIhN74WS*74KUR1)rOcE:$D7+3T=BmNTX81af9c#RGbek/XUk[-,F8*T2_565D6", &
        "pGY,@rlQ/Hx.r(4`+(>tNIcLkKU,ByII88``W)kapiGSBisCY1,EPtb-dsne@BqT+Dg,<>T<B*Nt7_U3t)A0DEL0@Q;D[%WJ7yr6b>LObT*wB[SdcT>K=8", &
        "T/];+_sh]YWN=1pjRHo[Sc72P-W?,VjnRVXpTf4gbH5O@lpuw2<A@4ZP,_R%37p#QngR]fv3rVyKfGNZ8fC>t$OH4y0A^dr^vme::#Q=P/)r4Qh[$E1e(0", &
        "*i38>OM.sv5E$7c5qF_5^Xj[WI0NTg4W9x8+W5T06ZJv>K52(dV@YjFPd)UV(5;`[S@A#P<2tqTNRt#W9`a$hZ:Q5QQ2ClUAwSlT>fY*mg#L>H@$64Y43Y", &
        "b+5v.yODSHlF%E%Yov%sQo8x)FQf>4C%63ITp=acWSOJF#)-QO?CFtXU<HF:/*>.x=[g(pNH()hH9+Sahp8]5lJ?1Kc[/Nz<RP2K4CR4-262JjD.%$d_jf", &
        ">.Xy]Zm3(?hc4D0Yk^lE-[Exx.kj/>,787s*_a6(Ec2n3hnUrnYI[94X``EQ4o6W`l@/cR:^h?4#iQ;1nEqN%Tg.(bKOyD9ctJ1:8kMl%yTY)VRw5hfXCw", &
        ".0d9*z<2^Of0VAXEn#m`MwxdEM0`mjT]<UC%d>Cx<w^l8zgvPru#0=PgumH*a9*#djnQ^[pN>G_ca/T:SE/j`a7[Jw^<0-@OAJVNxE>ZJPX;m<bsfk]rwx", &
        "e@Do<<Q#]CXkN_=Y_k8aBc<mw5[u5y?PGMQ%.Yts4>IDF_0qdga0z#@47JClD^rf:YD[+OyGymQKgMSbn`7$El<j)Id#E*:+..SAwL5lKLEPl4zIDm_rcM", &
        "#Zqq;5iDK]>aab$:Ug7iwIb==jcAP(7-b<HL>W?:O@+O+vV3Z@P=L<3?PJmHin70SlhO9/W7v_ITk.lk+.UaFW+ei?iSV`hcpw;Xd;@.)dCyoINr]aqMRk", &
        "G1w*^U3RJg`7(#E4A-7Jg`0VS:q7?hIx$%zko7ey@>/M7%:sMXc4U<kj*9nVM/cl=9n)sUl(.xs%zT+nRd[k>VTeiWv^DE/fFB3@AJJw3fB+A#hX[_V*<N", &
        "Ro_7%]Tk3Qu;pobT+mP8M?F>C$R+7aVbcXUQ>_,74i<K,L@[c6M[hw<:EP.iWW3F/==?K8cjN@`%hBR415?3(i8/14bZ/GI*CV.2nwcL7Kw:18Q*e-P2U]", &
        "y7)C@;v*mtC#TExtlvQU69l9J8+=Odm?::`dg]QZiQ5Di()S]rm(kl>?*@N=zkY4Xr2W7e;fS7t3P_2gK>[,X%nepAcUk*[IN*8Nt9ZeNL%/Y9HOVzMbN<", &
        "u8*O]*BEQCfmEc*ro%uo0MEsK%a35rD$%0zj^3oyqQsS?o88(s8jUTQv*ZUV:e`ZQDpY=b]AI:e1FCfj$sD51)$Rs82Cu)QViXPE1qCeWOjeuG<R#Qt6)9", &
        "n</Z89@bV/)Pv<:=N`749#f[0TQpNZ6hGJ1#y9de9e>ngNIeGMIfTb#=g+p]fo[ZWW@vCmV6s)G4=_9Na..51tG$q7HQ#kZ/XZndXTvc]J;b0nWJ*1CYT(", &
        "O//F=vd[FX-]);G[(OIRHCEO2BDpQG[wW)fD;o*/.$NVkkIsw.woaaPPe%(ih3%BH_fT9V7zFUDe8>;@5`oQ$A`fUan3M(bGJE=.@Ya8fxLTUvQ:R=+RRr", &
        "PjH$1bYyF0Nri>o_v=M3H;p4,Hj?Y5U3@$70/-7`nG6to*Dxl(6GMx(r_3[=XkQY(79ef-v$nk1EdjU$M*DUNFDWfK8>-ht@[Gz9?9IUI*C0/NbW$JZS=[", &
        "tgVT;9oj1c.WXqG*YWBics8e*1/M91TPMEa.NujMwKbYAx>9pl6R(?+E%gTC46%3077<iwB>]jsAOPg,m:Xi_i;OCMpQzc]G]F7>F3(:iu`XLfc8>sa;Hl", &
        "I]wbg3O#A5Kw%dM)p4KBL%yZw5vCB7I2Q;J./b(qW;@I:Xoaks%Q-UUr)xQqR+7c-0>7MOoPe;f->ZYv)AsT`2;qP)-lS8:WMrQHjoW$]Z;2)*7(eLsY7L", &
        ",]v?u$v<_x(o3BgYPoc@?M%3KfyFavd^DN<w+p;TFn2DH)-E`P,pMt[@7Q%Jc<,Mgg;-lsRP5X;<XLRk2,_Fg(kUQ)$?nm.Xl(V*Fn2DH)-E`P,pMt[@7Q", &
        "%Jc<+vUoYFW7RP5X;<XLRk2,_Fg(kUQ,j,w>jZ.zA[5FRf%DOtaT?WIxfvQ]q1/_Yi:I/,y.NZdVID6Qm%hWuEDM(-Yc4ZBZw6o,W+#xnQg,lt`R;p]ZUR", &
        "Ueci0?/]^>]ese#352q3M]SFu+LHsl`kyaE#jkwU)s/W9:(:nw%%Je1RxJKM[=p>_60rb^$xhsJWlUC,1NQl0Oh[k4Rz;,^$n+;Q_2duNek<1,gO/?X81]", &
        "#D6Vt*.vcz]##HhoLFis#;Wn,J#$-_bw1x>s#)ME9#B(N0##H-W9=P/rq6Yjf?T.]Gw>QQx$Cvjk#?vCNv%>A^/=:oXcb8^nw2$gNv%>Lj##)M8d%3bd%d", &
        "@t4#Zqbv##%9.mzIg/9UHB<upV;p#(D>,X,R+e#)GbosgwQU$35KeZ,PFncoNPr`vTfd)zBpJb5VLA.ybRll4b^Kn^d)biH]thx)<2CZ>JhBAqrx3di[oU", &
        "7K]vtD$lj4n3g@*pz`/K:4i*Ut*(++ffXN@q#uhYBidey4^rjs%jR<?)zB0Wr6x;-sMXq5FmxT?n_pl[=G[J@:UQkU9+JJ-vw2%*s*-P;)6sd-UDzZ^<O]", &
        "eQ#2TRs.ml,^02(orU>1sdd]OH`Wkws)0wDG,UR[<sdnTz#s*.s6caI.Hv%ezwOXDJE3AL*r$guEzecEX+4i*cB]9TYa1SRFTtrf([ACA%]cT<E:5NE9@b", &
        "O`F9vyj2_cX;@?/@XVGnEF*XA#5?yZw=5[l1_n1R::b$0*ZFGC,Aij]FmBph/dzk[%;pz6zQ1P;+xSoYsqVPJ$X=gB-Y+C./DZig;*CFe36H?nC;,`9#Tv", &
        "`%hUc.E9vZ(XV<ZrE6tz8`qinDgobn-cF^(]8M$sZ/l`dqPjj<BnyYh4gXdWv?7>V2>HJoE3jF4,%4wjG<G^?JgL>#KQ7iV/_8_#s%<=]qDbDQkQnjcInF", &
        "b)#pG*$EP:gVi(^kRcb/KI@2ztw=FBm1_f+%tBQuf?yQ<X^]9oMAMlfT?gJGXnL-vzg#7X5=Kd_K=$@,k9RIZdaZLqD:;J09U`$<9#Gf9hyZE-DIV8rq,0", &
        "w2(*uvb;Vc2mIf91hJCMdJpz+EIvPc#dZDXo0fFQ9C4Q=D5Amx;l3YPrMIY,Jl;b04xRa]gxS<`H]qF@,We9^7$_Fp.d)/P-)XudH)45u)Bzy5L/fk>2q7", &
        "7_.5O5@nBr/)]x_/55GyXA1hd>oD]RGmIFh?>)8F4Ug%7Z-s=JkP/iD[P9f,ld1k5un<YOynT7xKCmSLgWXetgv(zMhbu;Yh+[VHMT958`0X9(h3AfX4CS", &
        "vHg_dEPaNlYfiro^xxY%Si?be?+2H$u#?wliGdWd47`+J)7_Sdvw1[-xP-L(Da5h5RV+ARYHohAj)/,m.5.[YS5m+b)gH23%?xVn:k^Y6F^8e%vueQTS]i", &
        "siMlA(T;WZEX8wrIfpIQ=o:A4U+y+wO$xH]Pq:G[4q.D=E0kIo_UWtRO=u2n5j)d[4qK+0L@8<::;:VR@i<*z,LL9;u7^To,;.3w.:q.bJHGA)iR>OL?X>", &
        "Z_tlHi;lthoZVt5g`vtxC(HW(AD91lu$MTC0l8O4vB*%,HjPJI(A3(H$SgL0D8RqvzD_Po;i#<J<BcI2-.Z/Ui8*(^WK>#`x/F.kd)*t2U.H/Kd,VJ7-A[", &
        "e#>uSmoKr84b<qNIo8Yrex(eBu>=0K9>(Xc8?pJ]*]mE)emq@MtN#9no/:ISX.Rq671bR,KRRleRqR/jfytl9?s3qlwJClyNZvGtg.0G;.64IH-4q.1roE", &
        "f,P3/;L76rF`C;`.o*RX<Hezm)%tzWIiQ<X]SQAExf(L(D0AY6vjVfxmOF`dv(L-OX0BsSUV:j8d#PhTf,*IC5@r2*huTNT`w32ryn4CF-DFCRPYV)1`D$", &
        "Sz^JqC*fMWpuHS0L6q/D2(T0a:f1MMnLV9%]qPwo3I2cXvXX9D:bg*iPkl.DzRkS1LWEy+;CA:Zap8Tm1t;x0-5MSDC%=9UaVzr*@GRL)Sc=bjvFG-PNli", &
        "__qH)NUklmc5G>u9WGOl2KZq(u;p6$_@q9BhcoH=41j=uWTRwQ=@7<CVn]0X.-><>Tw:t8wVU+x<i#ZZbbwN_rDj:p^3;yv1[pMP^]uoRVW_;S7f7>8^cQ", &
        "$Q7si$#o3bLN;%Vlyn-s`.l8WzY^)v+o%_E?+]vl:a6XDR[PU9+@9@b/NL)XOZDwIx0-H#^/t8A0^(mEzZ.wIo65ETvHiD<cJ6elw_P^Z?m6u.t18/(R,:", &
        "kSup95v%ITbW9mYO1O`>5i)BzZ8p+Cj^A3t8mPA;l4_HH#bW/bw8=XrrCWf]JIhuA>ZjEeP113Od2Y.lCF[9Evz_^)8w@zNX/#uic>W#bWn5j@uS#E,3d.", &
        "s)Hfj:?`.vj@].BdwVSGr=[jr5c@+cqs5mK+GlVI77w(I)^w=qo69:HCLP$p,*79>+R=%(jw:Tuuav5yzw;vhH8,T/g@)[qbBeOmbJ%11SdVYaPI@SNpv)", &
        ")x1Idm)JtV9/c[lznIsKkdi7pLkDS%d8p(@oSqperUJp^^5xBUyd;wF`iV6W>Kyv1tYtZ*8DIX.#iSG:Pz6DBNW.R+5A=5CzdBAS^eE[:`fWy_OO41qA^)", &
        "X.>5TO%j`Um%g[Z7Ib]rSEl07l`QHcT<>d(90Zek@,o(^gJJ;D8rK+XLSk,I9i%f7$:U_VkGKOaGK`WQ<Z1z>qK/r7mQ/(6Nugr7loeMYJpD%E>()Vsk+L", &
        "Cw9>]81/1h/:ws[Nq^R]_W.hX*>T2Qj4@4WbfrSd1P8Rb*OCZLS$Aw?@/SA,;PwHdZw_AHG?09Z9C.pZnW*()fp^x.59v+yH3Wha*>]p`33gi6ix[vo+->", &
        "Lo^NH%j[0l).4N9.+T^(3tgVftT(Hd,j=3oCK>p;LZE4C;YuhV%[S[4HHQnF/[<v-?IT8Ydskpr%Y(8fcvm1CBsSQ4%q4A(?tMF8ugpoSUaN*p%ouzh3/+", &
        "JDGe$C<r]^RK55i=6R:v_v4-X@-^duq6RAnP+X-Hx+L=+CPm@:o#<,%m]1jnKj+C9M[6IDvx6Oughd2%#ep;Rd=:T>Ifs0VK4.-.iGn)Cc4Vpv2oKE7<(a", &
        "l?C#aV>%YiDL1hV+f-12Y;Tt+hH%d9$8]iM%Nd-ny%fE$K^,8T3])+_e._Q4si*(1)[824TzCE.H-GO-`;:.lG7WuC,qc[J6>+DApo-g)-BHFdZ`vu:>kU", &
        "es.gjO-=E-G%zIfYT%2i*H#p^0NUSxx0Mk[C6J^)qnOm,v/l0=2CSV*_c9ZHVjzX%9T9ci=NRA;>`g3t$5DfLnssMQPK@>0v]XqjhDwtc6wOyL,j+LPwhm", &
        "vy<k7zGR?u$b.7kk*.16?0-M[Qo.w,VK4mfZh>hR;V0IH$cpD)B<zl)(i^+FITN,d(q$8gEpQ9)mxPs9%4zI+;[Kl.2.zF)9_dKB]SWd+4(p`R4yAD>Gup", &
        "@r7([*?Zti-?,UEQgA;4Z<xd_?7wDaoFi+^fQFaW4dX0oUz=1I`Xfa.G:es]YNTK-MR[=FI5<*RgxVJ)WE#zaces*^F3yz8;m]250Uw=1I-dxUR/%(-uib", &
        "ri%4DUQZD8.[4ZM5iTSq)CSQ*3>06Y8nORY#,7((.#j?N15DHc#nB9cER)jIfaM`J.`mec2;,-Zh1eX39=SYXAH;vO6`-n#U_;#R1/cVwojr6^Mlg.IgN9", &
        "*+1=bBm#b_80;q(=4p6J(3M4fNe=8gjg*,$w7Gk,$kE9BOkQ_,-n@hS>/s=7]wr;O60Un,p[]TWZhruPyJ8<^K*XG4dY;>fgxhC:==%P*XPfk*kMmNVzf1", &
        ",`:c1>=^vx3/EK`Z-Y-21CS`@(<c9DB)Wm9OEp+Z,EOp?HtJw1$d:gv1oS5/kR4_hy]g8Tv0wYcQf%G[mpu2y95Nw$S%d`EyGnB>Uw8:Q,NM^:Ntsio)R0", &
        "L(aLaOxJPPQswWXw8@$.%S%@7g@lt2VdQ6XG5EkRF3r*X[;Qs@$v/%f>F,s`cTzrJhRvO-eS*vzPK2M0zt`V*^CMLaJE$Lw%qrls0j3hCZikXP/8BdV%_i", &
        "%/LGtB>km4e$ZjIUp-qB#8#K1-_).1v+^0C@Kj$BU)M%pF[qS450(P9vn3=A-7[)[9r)+?-$?ES3HSMcqk.S40?Rr9:GQ`LuQ+;<sb3XE3d9^d_*tTFMO:", &
        "^.9tZp7u6Mie6OiW2Wf0pFda-jsCfWQ=XuOLQ-_$lW=Y[nJVZ[pyRK7d)7qZi0<EF3RZ.i#iul0.>o$GR^Z;$VMSBx8y:*X9wZLHybP>c-_R/Z/scF_qul", &
        "yD])RC%YFutk?*Jbei5qkIVwE,^E3:WnL@4,IFcCiy)^N,*_%25Mp,Nk#FnoHzQz*`3;U^ISHE_H/^ssAr5e2^9r)UQv8JqswufEr%`-Njp30hdk#C6j3O", &
        "TD(56xh_ANhFTXKiY.Sk3Ou$YsNK=x=dNZcL$=L+<eRAy[OGOjh7MU,t?fz>K$7aLMR20s3h,ueZ>Cf6^>Q.N_TG^sJvpV(L%Ho/;.sH@r0VI/GD%FzUZE", &
        "6CfQQQX%0uB9r,9Cwu?LrOtw)tVnp`4IwSac4V;r*H7hgq*i*LLe$fEgbGq`P/LTYi$RMVMlG#_KtcS:_Y2H=Sv]ON?3:tF?@-LSnp<.BJw):hbAD(?bEe"]

    character(len=118), parameter :: BLOB_ROWS_11(100) = [character(len=118) :: &
        "jjp_7EC_wpqhEr9EG<tjSf4ICaIN):5<;+p+:93c.L]=nTucK_9]u0zpefn$2^`j:0GvA/F39P2<ulr-5[Iuje)uG@=XKBqv#,vrgQTkk+-5+frWGpoZ(v", &
        "lBP+[O@P12(9RJ2>]?Ek@N32Z`[JC7;Aq(69W#e2e,B[0TZ5eV<^4gdUoR#Ho#HDL.CWZ$7Mce%V1,JJnYXU;`ZB=gZ]bh?;B5Z,S`Z#atkNA-#aaYc5h1", &
        "h2R6W<Sa(AwH^/<2%H=I_$?U9$G+1,8]IaK`nHReb^r5SCb+]Wfr23S0)4cI_c%D?Fo1G%qL3cO?kL7,W.SD.%OijZnEUXNtqx.r5VH]4Ud<;pS-z.sg6T", &
        "uUet4?W;9uI7>saVWPWA/,o%-uJ(TFQO0pddf]bs9)<?5a/(Au8Fq55iZap:dN+.Q;+6QjjVFdYZ]pQ^48W`Xg:E];:kELATdAq5C@zozA=4?5F7yoX9I_", &
        "cqG<krrk4c)Oc.4:L+$MG=lQznb%?kT67c%iWIGs+kGJXDul__R`p(uQRcrF*a/K9vMTn_kAnEm`AY-3aUnw)s7WcJR?%S-=D.b7MJ,BTjbH`..W%d+Ay2", &
        "+AjRJCzRvvo*g5`VuHP,*D[+_v7b.xx;i;3EfV;Dwz1Drgj$<T>x8QP$z+bRu74/ABnV>*9bVNuo)my(aO%H45YbjLa3NXF@+:A7Q_qoV.FbbO+C@J`*K4", &
        "XuYnNP<oefceAMQS=Q`WMt>eQpd/xRTr7*-3a8@Ek$eHHVp*Vb_=E:,$Cw[GBY>IC9g[:fGncr1(U2:>8/.5[*fY]0c@;nPyrrC0ng%/%5%-CL;mfSsW,.", &
        "sb=pE_CWPc81P1SoQz=vAM:*;AvIi)aCC:(42cB%cWo[uvq(2:ULvHeNg+>P:er8)ymVx_BCx-i%>^Ghk.s>irrC?VIGP9,G@WxWwv779K#1XE4`1@=LHA", &
        "u)_[Bfc9a$`?+v-8?Fo$Ajv/j;kTrPRYff?RYI=pR_aS6BH.Fa=QPw5GR*CBf)W^HgIO<l>AFOF^,rELXczQH((V0swY**=@7N=xM>,]Jg4uexq5M/<mFS", &
        "ijNMUtymJ[t-m3Ip#%[$?8L+cugeX^;wwe=Qy)X18a2+<95:o]`a+;U[:?]U5I5:WRxc.*=BBT`%3$Gn)sA92$m-SCq.5,slkNw:3WLc0K__JX+T`wQqA<", &
        "@XuIc]R):_W]b[_(`2y$C5WKgR9BfM1t$(X>Zve$_P/jLOk2Jxr/=@%Oe$jz1DXTaPywAybGlVxu]TR@RBM=uoJxUT?-/c%Ea5_$4-<+]o,HdW>]xwGAo^", &
        "lPL1yNB%thfKmvw#m-W1x@(+4[b)X7c[6mr[=H3[S,@=aAKTR2U.K*=JoQDZnN$Wam==Vaqluo(y3kE@Vy]oALyN/z$D[8wVVeD(r:=vi`UM0*9/fW>*YV", &
        "MyZ5OJy0hgK]S@PQap/VRJV3tLp<M@0G5YsZ>TJ?Q*D:hUC73NiBVYe_6+CMfi3dvs2)uS7V>m];;Y[VB[yqW1yy#ZfdP%f>`,E:`ur2NnhB%Ux9>?uNEr", &
        "v5a@=mgXmt@r[7[;gh(>B%e,^j(]/N=I49XN9Dhpm.824)0]AAa/*>QUH`opd[eFx9H=0v84SnNn:OZ^nV>eg0qt;l;.4nRq<p.*OSQq%_,re#`lI38/L#", &
        "+xT@k;QKfgOzk0[bLK1Wz,J7GKfF)7lyFP1z?7A#QLe_SW@(aS.9oMhJ=;P)mx4%:ByWQbe=F/Be9:9`vVKO#@4L`5-dj.b[8TM#;V.>5uv8WLT3x)B<;K", &
        "Xas)On3_+d=N0=GM[2%YDk2e/^VMtM_vkZ)ne]WS?-=FsPf:G7<:,IQB+vi?pX8FWDN5?mSuHb>q0F+L6Q6WSTi_8f-EHQB[FeRfk86/T]Qc4XrWPZ9CxN", &
        "$)4_E1-[`=gj2:XKckKdgK1+m):Q8bO;4Wy6RRgoh8).SEv(^OMg(v/8B*#TlX*Zv$Y?sa0-P?J4R@F@rhc;b//Z%^3[SmF)qQ=buJ+fDA@h1YBBIyR?gR", &
        "av5E<*I;.IX(@u3DkLIFobEqfi,*)$DM_QTLY)[UX2<Q8<h7>6A0^U@d#MU,V*NWQ:0hmsRe#;q7fpo>D1Umn4>2;B;lUxGO*:ShaMUI3Wx=fXX1VR>T-*", &
        "i]Tbg0H$eLll^B.X3:Rn[G1O1m0V=zOD2tfo+_RK./hLkus$v_to<hgkD/gVB,-I^c4JM2W(rGE.7`Ta3Ev$@wa8E.^AE+Tnvei3nOuF*d9]yoowtzrV-y", &
        "<I>>*OQ]<iq]b4sUcaDl8^cG?lO*WwZgU%S]vw,#gr:$K-M4P@pGbJiqFu3M=:fQz5stFthO#X`v+4jIcrw-q%/R9tO>iJWvhV][=?bpY56]91aWIkvOj:", &
        "DkrXyI)z*,$>0m#P/JpiNi5@:NAO_jG,8e:hTz@vr;$B`:3w(euj_#R*j);:$+FDoelKQ1MtMDKo?u#/hbJ)x+PMX[1;zsh%f`u4@YUwINB6TQXxh+0a26", &
        "Y*R@7(`<wi.<n#AyI/hLhpcex5[9sU#g)S*P$-wp5AqfPM+OBs,dsj%P-PdJdw%#?auQ#VDflKX-uSg0vw?RAwDdag3nq),`f%p+ph5,uO)>1OAKuI/)ve", &
        "5lTww/7z`NMo.?S/bB/WmdX7,8u/JI_uSUu3%4e`%W90eIXQUR$`u4s3Rn*Rd9mK0uT%efG;2D(uWAA8]ogf6$e=^^(Otj<jFHZWC[+G$Kb`)e=-YJ;ox0", &
        ")DELj)VY_afwWMJQE$]d=,EV$Ae1hsq_v2,(9I0jF.rjN[u=89kkAh$1Hrr,?;Kv=yBVMeAp?-$]uF^_^#yKw:j(fUEdl=$waABnmSQzte`5.Xz8ir4Tle", &
        "/mp5#m0frVL(lSYr8uPN-S[Z@A#`LFeM)*CucGfUyU;h:^V^1UwogiV$uMq<J(RO-n>>dC+UMV2V-R4Snyg=SN_A;g[$b0M*1%EAghKj?i.NP0n<pPM@M(", &
        "BC%YN4bH#=OPC3jZdXn0Cg;*p6N8h:*=2tO@JNP[j9r=r7Gby)>Y2imlLup;O]nYVU)Diz(=Afn$1kwu`rrrNU]-`/RY^k+,Y@-c;Bn:^bIb%W8.BYwbG4", &
        "]ci5dssW9>JUwid/E+>v0m3X$_lGdz=q=Sd,T$iW,,$#:J.mb*[HcgzHNh-[^b1<0f=(6JpHPZL)PD(2eSJImsXHy9O[Y@zi%[RF1J:`K)9v*(WHX3Y?xo", &
        "4JALJ-hdgSRnzMBO#1fV+rkKI01t$6^PmECVt3q_AI-<-$lyk=IM-pWuj6##ZrQ^=p1bV=o])z6q4mJ0XgRNh2S^U]z%?5iMACau-WAkrqK0YKv7[Ta/6;", &
        "_EwchRNSey(7VkgDl-6e]_tkjd(qOr?HY$:V=tHe49F/RaO-UA0YY?kRi6?IHpOPWGk5IvHaE,YnreG9]opAWE$tS5jUQSE]$@o;9Vu9LnsoW3QaG*]CY_", &
        "?F<]Pig78J?#g3dt.lPomUEjrJt]D96KM,HMW,U+_JZC9CC#?>+v^p+jW+kSn[JifRU$VNH3RD-(ovXs.9<cxHVFDHWvr%[tGD@#Q?r[KVGVF?J36h5cwV", &
        "]+P@P[9d(3al8S%eE@(8D^9cb2<<+=W_bY4-w_yFS:g>1VJR3;D8dgF92Hg,KXQ_Gdg(IYg:s8Yt/G3zF#IXY;P-@kNLMW``#YU,uj=$ywOzWb_S7vYP=S", &
        "c0*B%6C9f;P2lD%O)XuCl[r/ckxw4I#.XnA0b,IU(`EU#rkSns:p;6O#e,,G4tb<LTm8IwJle8h@hfHt(t=K)pk,lFlZkYD-#k^eEvr3tvv;.+ia)%MEGI", &
        "DvtgfPkaw%h*DE19H6wA-b:y51?CtdpeRyCs)ZR(+U]Yw0O?3Qk`m?NOrc]Q%Y[m[-8(r,jCorDf)GX<ljwKi*s@ORsB5,-BZ-Z-KVU?Zmu4X%x.G*^[eo", &
        "d<#ltu7$3L#WH_.fHHh7*KBouAb`=tDNnqE_qz^<t<V2(80bLu3RhQ]^P4K%2Hb^.c+>,#rDMW;I)m`PhFuVS9lV-9</sKq^bPJ=HhT`$Y7lqO$0;ZPrG%", &
        "K.9)3.-5%Bw$m`yGZ9VZp/p)yttCW@/DQ0$1@UlgIqWQANd=MKp*GW(y,mS[Lj^s5LP4Fb$VnABYwDqBqJM_CVQK:a0ML9>%?:E7Tc);)T_/1S;T%JUY3J", &
        ";PZ])GZCb^`_8F/.N^_t_A9Z.(-XimQ]hec))u5-cbJ+R;8Z:S=u8>DZ[Pv[o^;/:>d%%w>elD=OCt<d*^1296)AR5i%A^D1Z/A+vfgwtS`OQ3$>Tt%ng8", &
        "(HL_+iXsI*Pc$v<L$VE.ZH/MqGr%[/]*XzMUw;[AX3LvgI,*GL=cbQK#G=7o_LZNT*d_jlNa;*2ESe,lr*r2Q_(0NsN(*t(Vve+R@#gds8WHqxcYZ;#tX7", &
        "cShL8Xqr_VJhyUP/(IKdC^^?v5fxNraR7m^:/b99y1:$99A?$P#a,RSN)VL;0:ve#IYVu?HQP_ucWu8m%OcQI0s7tc-+kw0Zgm7MI:i_]`j4p=3Vs9Yf:(", &
        "M>HDSBqZ<WEZ^ssxdlIhJ0JF[0<?QoW6?]_1/TOi[-*9aIe41-eGPEPsEH^7ZoFwS.%2qEH)MpcIkqTn)4ZZp0c,se70]i6F.*D93*_GGpkfRar%[_l:Vh", &
        "F8Ml0eIge%SQv5DBc<AKBl67)_CTJnnYJ,n0<q+L9=d-;9[b$P(+f[>:GKvN0F[#b1l`Q.QEz?4KHU?1U#-#CB#T7Yfi4%2NWp1UjxDRqRMZ(0NIMaCl74", &
        "Q#e-%LOhI(-lsn2w(hV,owJ<2R<^Q*00(gN>$#mpnUmc=I@v8YwEJ$gsA*8Ea-wpC2]VwB:h>PbYXhW7>@[0V)J%j,MD2Gw@*71rkWi^r0IVdGhw>/.$D/", &
        ".r_k.@e6wtbTcegfc@>,oO%XsV_6I<+:LvUJj<.6[0u705h0EoEaJ)ETl<;KnL#bGR>rW-_7i`x%.@-+-ISxcQJ>1i>>AIrpTh80FUCSg?/.=U3hoVf#Nw", &
        "<1S*;P-)`7%owwW]lg>:*GVqAPdMj6Ad0r5?s7p/X05zs84#xETc?nfgBh#+;h0k[ET3FIm@vmtTzEGV-]5vP]*HA4K+Ap9>^*qmRYFah?mMRFsaI]kKpr", &
        "pZyTIZFMI*M=?7VnBj$q0P31<Z9eKv.YD/lxOUF.MR8:yb#xatr?9^]R1>HoRD5ft=b8CuKJ?8gvNi?tW,$jro9YcD8Q5pPI(4)D*CeCLKjFRppKan0;tt", &
        "jFXoBh+Q>s:e3Q*fZ^%u(L$c4Ch5RV;o%-D5oTVJdVzJOh.._V-QrP_nLX;mH<c.Bew`;;)#/oN$[^22Q9PoEXAjsSuJ6#^xN?UqseHjbb3tqDHY+%$+sK", &
        "ch:f#7vCa?XiwjQNhlVBo27TFbXLFoo@9D:T$q]#0FM?ed+6T57TxzG-).w$fC0F^e`=+>m6/u@t;>JA0t:^RaE>)gicjwjo/KhE990]?N:;xW*;Th^ES?", &
        "$V78-(Emx?26((hWIk_:*X?8EOe)rw)$=/%-a*`J-Y+eB78d3_JkBnzN=c-[mef[>OLMrD/HI$LTUMQ.:hQE2aK;-*D)5/HDePwDVZ_JB_^_:]`q=*e=.S", &
        "Fx/F^aqIer3ujL$#A)3x/%TQ)mV1-;yAnTD@I??t^PykW^(i39xq6M5.+)6^Gp/+*7;c>=2tC18gZ8$;^%Ds>U.$V#G@Z/IDioDLbs3fhsomm(-l0IV>3K", &
        "/r9>yni5NHREdp7U)8HWCo,r4k^>Bw^8/*i$(L1tnv%go*rJKG#/Ys>JIc2[r<k?)T?IK$TQ-ujtdMgul3BAG(vnB<W-xyamFP+*ZOtIzHNs#`-Ap,QOU*", &
        "rDXES/RNUj2[eDy?Y>-d$n>ordRzw+WqvF>rXa-fn2.I<j]aTHXPnQiMAR<4VcIfGM^RE,Q-GG,HUJ<ANSy/Sn.=U`oWlDC6T=f]KOv3)BbqwGG*;@*Bj>", &
        ".>a:mY-bs<tc),`g_AhQTHQ$v<l+1_6IFj<%?Em?Zcc?^nwyRIBk,#):_<.0C[.WLJ_E@P%6xLBs`a1bczi4f[/^_3X-Py8V)5JxP7MC*p^+#[%4;zY*$*", &
        "vZDRDRSK^xEvKtc[lK</ew#NOGH$>U71aLW#J;dc7WY.,j8@J,X5Ye6I;KN#EcFt$]`7:7S$BnO-=B.=@@7gEQJMwY7*)aY*Lpxr`v0BQt8D.H^#SUI(N]", &
        "l=`A*aCRq/olyC_?mH._efkqGNJyWL/t/WNd^C23Or,d)QSko_P_pTa_aftKxgI/lmG*aO%EUDB5-`U,K=nw3qg968j;7H0#W29.6pmZ9luL:ck_I?FUpc", &
        "27,1S*(<CUP5ou2Q-`<E^`dVtVrT9eNXUudG]HnuMO2$bUQ=rO9vDW;8/ki+kHy72yAyZS`p@Acu(<m:Oo<kD,6D3Nzdk9nwBfh`]/TJZXpmBqJK<Q4)2>", &
        "rUM%AueOC0UYtQJ0wv@3kgX4Zzph*]#XODiyVx,.3SMPN,DZkQDA(Rz/;y*$,;Z2EbQqTeau#Q.voBS0N?7K?pRh37Jj>4Wt7DVkneo`GKjw>gv5BH@(PD", &
        "T]dsbeagbQb,T_Q6P)?Y:+towNrWY7uLk)7VvV(X6X5j4Eq5$8qo$ec,se8]pWxZcWV]M[K6^WL`^sBz*AY1M:2k`#D)jvU@7-X(3JtzwJG_6:CuZY:%ul", &
        "d+%3NY8m90vA8;`uC.C-SfZ7j=3d%1Pwe1R0s<J.[#FTz;,WXcYpc-(RWusI+wpnRcJnZ>Y9neCYTPH8ljf9z;@9ujfr%rm5GJ,8h3+8Hj@YsF`g1/Y_0M", &
        "VOSSRwu+hMy>Ev+F2#(QAF*`FH7nOv-M14KPV?G0pyFz#3.?ImUCNEBofx>V90=fFvIvmi>cZil2*vB<]GP[nekwh9y(k7rdjXiJCskk#5ju1AnTR0Vsv1", &
        "AvNyQ+MT5/AmzaCa8B;sRmJr+B9;8>vG+5^1t==HFlK.%r/fQ.USS=$:p*LB/j>1S#.<h]PumF0M7THVpOLL,BJJRB@j$:cYsX4;N79qRv8W6J9CP3t/m2", &
        ":>LusYHQrXJwzs5i1H7%(Ik9^0xGVRE-WO81fsl?GlrO3xGD)7a+.ebi`$JhHG(==.-BF;0f@J#VlP9vIBvLRU9XMxw<yLyu*GtWgZ)bj]^yKQ*Z`.MJ68", &
        "%#1%sa<$X)<m[SN:do=4nxqZN5Uhj)7ooE,Nyo3^i3qCcIikZtNn_/;<I`asuu`w]pS_Xi#lI2tNZ08Z0G6wN@V[Q]^H4VAk+a7U2eDQ8V@*m#7JKHpYzD", &
        "5,_i2a)o5yquSwncH3_1J9J=n`/4%U$+ugH7cuPs@MDEArX9?wPm#Z/^$;iM7VNn)OBte%D#/P_Kvs%?YI9#oTYc;;3$X<^qBMk50bw(H0iR])a.e8H%eY", &
        "0u(xfs`$PffL7m4lCJz+V`g+/#I<wrS2%Gi`yE^`/a]^PU?^8jF0T/okguksMSi#MY^J66=,[kJJAHlM?Xj5K7-iA)^nh5Zz/1E:+nFrt07JYa<d/6m>xt", &
        "?isD6IX<YtE7-m@HRc-fMK>#k%U;)/p`[)nPL<OhxVNFY#v#,tfIKt+8)XgF:/LkUg(iiKRpj@SD:<C4bI]/><G^=#$sC1<vVxQSaIjeKnRkInSl;R(lF3", &
        "y<[T(#ro^mU=L#g;pqO41_#)]S%QQbA;]V=>7@-ai.ja4k%(uVw%9?]]0kkpmduV6l3tSq)uB.*A,OtB>h`7L#FcAwC5_jZG08$@fjnDx*HSusVGC7oiJ0", &
        "4@2S,L9Hy.aKW%.rTl<)E]RO37N0iQO/Pln.j9]#Lj#iqMnHuCvW=nW*9Y=>%;2,6-vwZTv)I?T92(Au;R@.,Y#N@7nu$9qq[.PS][mlT_DDRtfEc+;lT6", &
        "fd[vQT<vD3*c#$@V/)5gkNNVAj*R0/FduC?E#sZCIue^39B.Al7WIz(g-Nf=Q^w]aZbhu9a_qgm--O4O+G>ZLfa8]u6daEq*-X7[R_wa8:yuvl.4UYE++(", &
        "z>lyu#R=(ny+5`R(_*tL:*7sEk0SL$7An1w%gGh?SFb.-BrtS#Z1^1Nr5a)6(Ugg3;08O.XxZ[GkxqKu,+yEQBu>9frn>%-G(?3v%,LUwfK9pv7_3HhZc@", &
        "mmf?j3szI@H]q%+;7^bVw>_9FqQAD2ee?,3>S2^%uk0C]Fq6*ejHq)sU4D8GwJag<o-=;GDF;3S/dm,N7:[)f5;wa_oI5Szf%UsVDO8B)-kErRuaVla5[Q", &
        "e1@_5wTAV-nnGS+2WdT@$swTQ-0v%q4089R+)[%[y^NI1uQcSM?enP8pjElV1j+)8RBsfZ02(=+xv<X%[Wpi,cQ.n+@:,+Wy=AEeP0>Z$orQYZV$$)s6r/", &
        "PwFQ(IQzTF/X6WpWZ3zRbhd-N[8wIHW4>#HdB^w-.`YZ7J*>pq;H[?6+=Lzsq)@-Md<6WYH*w*C4(?ALZJQ7jgo9vv3mKvJI)wTZdB%UEhzS:f8.^q1NKD", &
        "):Zw8T=/mtR?7$iP77LXAl@OM*QKzWnzP5Bq3fS621_V=rI,dVae425]iAZ?dUIBrlSR]YK:RCA$vPZJOtmZ]ZjPLk(:0r^18[/WeB-M5,@(5S34oI:L.P", &
        "8:y/(1/G]VG;f%;pFOXB/IjwfZ<a5VOoF1ZxXV*%*Gg02f@Z)lpSN;Tb`n+WhTGk7wV,V6MUq+7*5Pz;]ky+oFg3%p(tRyo:z5a9#RUMu#hB]%R>8]3<j<", &
        "%ZHtmnul1PL.%)mBRTv60^DEe8Y52U<PMdW(@kuE^?73nr]DdTN+=c:UE,)48iBttprnsq*K:#=on9h*x/e)BdjEuC5uT:^TsiCgRnyRWoMozFh)AUEt:7", &
        "d*E`uxPOOF%IK(:wZ.C`,;W%6?9EM+qpr1hat476F(f%S0^D>[Fam8^hf2Lqz$D(wFf<n+?TvoAgm1O8t35_i]QJk(R[#LfI*AlNt?7hgWFj1l$sGOXZ*J", &
        "vsH5lmY58q:45SH;ZNL=XV8LBT@W$=TbM)m<N%-K,siPR%77kMHPW80)KHek3=J9>1l$sUTSKM1AK.PRq4rUmX7;7n+^-)3Dl;GHF:J>9>2m+*7U]%MA5C", &
        "8CRaXOUkb4%?4zcq0QF%QC-*iV<p]@F0KaH/dRD(`1o0dWbp76Bs+=7OS>T4STIJB:3FzVzQT0snMtD4]*P)D#dOJ(Gx2(;B5S#P1]JJd:+9Hy>D3v/so0", &
        "n]G->,UFlAhVaKS(>pJ.Jj#U2N8l$%.x(iGLhc0L_i%k]G?>N9GIg^Y;+CQ0Gre(+6JU1N?Y;%25WqaYwQR(OzI%,/?@gG+JQeZ47evSWh;+oH2XG]^p<S", &
        "IP9xdfBLfK5/]=Qw=zHn(qbb?hYx/Eyo_y4z-6keIction_vUh4I@=sd37/dfAjGn`tLs:XIL,?<g8totn4FNk2Ya4j:2aoR$$%[42^HbwGeiK`_zJ_Uo*", &
        "ripN<cc>$UmJ*ZotX/2BJC=@zY.C._Z+]OV>QY$X7Ys9eqqTdJXM=:auG2w<BqbD:2(uVb$dUNpwNGXRpo-Dyt:kTY]tqqV$sJjpxEfiy_5+$XO1tBciwM", &
        "Emdqs-epZ,M8/i:Y;XR2eniMhhI9NqtYp%5.R(#-)-]ATD$H`tR.P^;s?/a_O8F-Uh%y`jlE^ui/qcHq/2<+C6g-^vm5(/>o+gEdS4u=k/gdd7+CY=$,o?", &
        "Ct@*5Y<er5fhCVTl8Ds4wwnH#]O`6^-Qe?g.#r9AS;1:J@ue%j5ahz+<aBfjzHullzagmOOk#Z,%o8(zkVE1>^?7c,)Idb/WXS$Yzr4e6?hY>6h5c747zd", &
        "pgB.`Yaue/$gZ_(R>@^8N.0W#FvUV%GXow0GJ>rseknhnIOpJRAZgX`ui$oq,REInJAP]90Ey8/^9sj/u?Bxdq%E)4HMDP8t3hBUD=lE`Cp[*F_Y3ZfYW:", &
        "2%y34SA:C9Y,EkIx4pd:b9fia%GKPcn8T8nxK,Cr?W^dxd,iZ@]QQ-kd-rY+;uZO(BGpo).)9xnm*8Q3[fP@+rbV?,B)CB0/I*dnq-S0>MiFQfyP,pW_(i", &
        "ee#kk.gk6`ksnX]4>Z%;1h/W>n:PU`qd0/lFu<kpq(-IzGDts[zB=cmSeaGcdUme2df#1FlZDg6QAxFzqR,OH(O#Zr-RME)W:[O][#S*sq/(*q=9$^s>UD", &
        "(7esM*<Q_]IJz/*)30;m[N7lL7#Ns;5nZ2dVxa4_XeCamDB/ugW4FX?FSlIKD:_clgg%=j,0?H[N8G(,HNgs58(GF>a+Xsd[QS6h6stfk5IHG-e4Q1M<P]", &
        "xojvuadLRnOEdcwQYiNs63qG3.31:+Oc7/bYBa@t[^.t[M%24?hDDSH[x:f@TD;-G@V;[Wp#@=]jUnB-awG?O`ouk==x:^^vMOH;cZ6dl/MTVQ,z]@*I2#", &
        "XKosOMFe8DaG,g3GW.AFX*;AJ^qgQuF3Rq7>Udao--*k_#9.wTqd(;o$pgqlM#lNo74z0:.Le5o@lkH<Z@Z02ve#5$K2zeLZkziV?K6^NoxbRXMZcuJb4v", &
        "Ih1)#7ZV4eY=N-yZ7sHwV:qU@RoCXVYCNNGqnF%W%W67e1updyldMSIRZj0,)iKh.]2uo[_(v(xp#$G2V:aodJN?s35%W<a.5%wF^?ge5(e#VJPO2tWg,m", &
        "9r`q;f-J_T.4MSG>.31Y+nZ0,0)[5$UpL?(w+y)f3T7QLN-QLToZ//1Wy52pF=VS?A10/A2Z+k)ANi@MH+zuv79LsYPkX-6=%?igii9:CuUB`#4$%V-l-r", &
        "OUN6tQ*bA2$yvUF#:BRY*[im9@]$]+nHo6Adb9gaug7nn(t/K?T0O$N37Uc[1_s_M@P^USdtNQOiE.vskc)e^_WfV%B6JEgg[_Z2M3T+Q/;hM*=swOR=ij", &
        "PGEo1ebUw,i.w<?*WuqqA=d<a?_hY/F0e/##V(ow#n(2$b]i)?Lf,mgwf>pNnDMV<0>.b0;h9w=Yiefte5K2(X+Sul7pH2/$^P<zwGF@ary@GJJAd#vX8D", &
        "ByXg[9-xdg^2Jq:)s1[WK@HOQAQ7Sf+>On:u?X0b3CZ)luMheC$:I<%(VWr7-+eXc30kB/aG`8SU%;Z64l4cFWG+9IbAb=G2)Ty++_?-oa`SdW7<6$40gI", &
        "-2-PYYF2R$3Jti=<5dbCnW18wx>36iBNI>ZD/s8_2kptWndZOwtW[e>sZuK5u;O_O4Duncp$kW$fnf8W*8N#Y*Ny.%_-z?n3>DL6Yw6.g4E;wwqCbGPc_b", &
        "0b^,1%mqJ-=mNl(WzGc8a@dgo2%m4A<wL3iI$p@Ndzx14*3YftYUCQApMFXz;jfP0>>##eUsApjg2M0Dl1R#O240)W2NPYiR:z*FNSwG=OkaFpjonTbKuz", &
        ">p>O`qsbPET/I>/(r3@fQme[G$mE4>.3@M0gXQKUE+kxqfg08+/g]G6RhfZ+0p6<XoFfo%s6cJt4d)*(HdZkZuA6=DR8E^+Xmyp6V9yZ8jt4Soo>2tF_HG", &
        "=tcGuJUiF9I0r%b:sq?@x94V3yL%Hq(vk#x@Ot+St)sa1:zR-Cg$X@Q`XYT+Lch:vPGDWeRYu4$=3cM4Gh3bjEwSM7aU/R6IK:XPR(:2#ncVg_7AlCk?xX", &
        "`A@LjvT?57ZYz.ROP16Ma63n;G9zuZ]cYn[)g3pZjC(qQyRRfb8QUv%-#H8hxSXmEGXZtgXE9Qa#Q%R:AEaVc[#lS9%3G0_$@ED%pGPG=J@`MWrEv@,_ai", &
        "AB<lmyu0,rvWIabpoJ_6[Wvlod;d(oq`sjPSS,Gxv>%jwWThFOlK#^uD`ttt,_A+x0tOmtbPTJf7Z=0V+7KJ.^r;q@p#=n#1r/Ur.+huk^/r#Z*e/.)cgN", &
        "Xw+sg[kVwF;dTpJ[X9UzM;G@iDtafCl>6nL($6WhkB>:ZIBUsH#Q$O5@w6hgI<pcI6(RAIk#iA;;o7I>2x4o;@2@M5KPwdy:9*<ib,Vf42Ea1mLTeFEpqK"]

    character(len=118), parameter :: BLOB_ROWS_12(100) = [character(len=118) :: &
        "<g:E`5HaOvR:kkC:)ATX]6M^re[h*4im`ff9tklKDwVR4HOI:I;GH(JWaDK9l>#^#NHThzY/ChO9kOQb^kD,55<)9JW$.$hF0%jJ,QAHkHrv]n%%MQsx$w", &
        "VI3Q@q:29iN8gHh`pYD5_H,oCPwdb4km0*r^^<6wp5S:SZQ2UGd)+khGJ.y?u))SSqShTI0H8@A+yd<;.(0wq@lH#07h+Beh-eF*t9%g]1pE7Q4heGGTy@", &
        ",Ab_OJ2K/w2(*evb;d^Dl,?^P<vnrW99.^o_*8;]QYxj@vpQ6qgZa>jC/KIO,mnviY=M$8d=.kM8yS.+>AQe$<9#Gf9hyZE-DIV8rq,0w2(*uvb:SZ*CrF", &
        "OBt$Lp`nMbQD7uz`tGNfL4`jX_bk6cIuf`Zov8Odw:WW[%#it;oZG4I:%<Cb+n:r#nw5yiarl$WX:)bPC?8_/TTMR-hi1=c%slGa8BeOzkL2A2Llr0dON$", &
        "62_T):3>PGfeh8j1l]BrNXk6bVHqL-n(3+YA2SQ,>iEPm2d0>fIe4fsQmM*rpO70jNoAuWWSdUY69C%H;r+t)$7Q_*hHQq*YKeOKRc4I:]4SMWw0UW%D*$", &
        "1QH+:f.E[`.z?5FBtYE+j:gbBb8_<vUI$$]sY*.M9]DVn0Uyt:abFCe>Xk`lZRZ`ihB%,?R.fG(Tx6ff/Pjit%*(89x$wIMKNNgZ/Ba$(ikgKn`;=n4iwv", &
        "L=GNQjZ:/.bE;jS;BETzn/PuUN(GfaE;0d`yRMroYrMs7gFH-G/0LZLQuWclJ0S8(PX+7BC.fcc_.,?uHu1jIr1sobYRWyFzZ-r-l00:agT=v+6x_rH_C^", &
        "ub3prh0ue@qye(;mcT#($g=w9uh#^.5w5L4-q8aUfB%k--C]oT)3V/e]QjthOS:3ldHsfJVy77+E4,d;mK8+qF4j@=*XUah=b`w5-E7VPblUwh=72$OFCQ", &
        "`Rc88Aj;JK./CYhFeqM4v9<xQ61l(tsdb6n;D[?K0nhoR[.-*AE%/ZgX*Qd/2=4OK*7e#of5d4j0Qt=8R`250^;r1yqJ<mH>JI(A3(H$SgVHZ28qp2mtPo", &
        ";i#<J<BcI2,;?A:w72Wc@@xnE*5s+=FgVB]^)rOPSm]d<:a@FXq^te#N+@<_X%M=<TGHw(6sSw35so1NK%iRQf3;*P90cLuG8L/a#%F1eH2a_K1TXj?G6n", &
        "j0tB#Oq#SW^ef9$RcstbFq7LXveIe>B]GXPK[?AWS+74*w_/UdvXv4W-Bos.+Qfe7)QIARRxi,r^]G2y>I:-QM3CP0g@9nhpL/,gd^rueRKR%,)RP^uel=", &
        "A(%twzZU>Za7$/dg8ej4KI%=jDyT$5(t0MrfM)IKk?;nsWr4Cd>vpAV*z%LNN7dL<xpVASh@WQ.(qsreB-rf+/TVHc4#F>y*?`U5g2P)%/v08/*D8Myz@X", &
        "wzmtYI4m0bG]Q.CW*mp6t`z]b$XbcU9t88KRaRrd+[LF8?>e5FA%@^aNV](gGi]Pon>%30rkLPJWL@,dVQx%QV4B(966/vJ3,v5KZq(yip92@m+]_)NUVQ", &
        "aA%(/0#kp@Dt;/bNE6/37gXd)^4Eb,)$U;0<($AGlNsguS-e]Cb1jzg0?#3^t(7eaVOgY@uV:vF=lOZSW,x2,eWB<6%fW`,EiIjWQugr8woI2PMo6QxX*Y", &
        "x(WgnJBqQ+7-)1J*PGukw*3vz_j+67t-I0,xU]2EYS3@`Fw<^Go<N:F@Nq2w6<s^8Tmz,-+HwjUB39)zl:DJWL]q,+IRy#PxXapZ[HhPN,o[w.hyY<fH.>", &
        "g:>cUgjei^$g`NxMp%qAd2@F7*)X#jXB];<J1b8lOw7gIr`z>Gk)Yb;*AD;KYfVX<50hzR8uZmyjmJ)/uzX4]>=:0hh%.CZ=z=pjZ`.WtwLZo4$9z9iJ)G", &
        ";EfE._G7=5^Sg1V5ReWx#u;Xj%(O,GX`/ul+Xs:/[tO8$yT6olr$*T=JxeJ:Mv?,8(C*M,G7oMOvX(2k^<KXIBy7TzvqiG:d(;.e=(IgjDPiyiF1K]S>+M", &
        "bV$zgs.U;h5)jG8z?bK-mRfg)<O97#C[>cYhbE#l,p:O%Pb3k18NT=1(>Ee`tnixCpJU@`BU=[#mDPWSc4.=>lA9UITU;ZAs9^HOHG`^6j;ur?ghpBe:+l", &
        "a?0FkA:bn`R,bPu7,1CQp:+mlTeV+^(diYT+[duaWethxeDV@M$R*f;g#bP7]j7c^N.%8oN9d,T#p5Lfu)6RG+Z6#$sPkS@v^p+YjK,Qe`T)d/5qv(D=mo", &
        "S`U/D_w$:7%;D:V]dx=t37[gpS/6hBJ]Vue`X+w)c2h*L*i]j51^CGMVK-d7O3$Q=a9qLi/@[.Rt46r_Mn^HqIB/loG;85h-x7IyxzPOmMPoO%=O4pQ@k?", &
        ">Z6;NW2nKKPoZ:h`^rT6kNCV7I9e5a4sYK@/SGF%s^]dC4c*DAhNpRL>]hq`Hc=h;s]3Df/;T:YsdMsdL5(+Sw$c,?<Z<NU*P-w-L_-p?=C*;)S=HCqZi?", &
        "vTsiMrjh:@o[]Wc$+7+uiaaNaL%G9vqqjy8j.[>3`Qr7Aa/`Ex@kEEAyUn,jtAH;6;P),uobbYJ60C1d@9GM095kaL(*9DzY<6$YE9J<r<ku$86[Tp*tWJ", &
        "[9t<bs;i?DFLRR`C@[MQl>9)O:d^>rK>Vr(1]a%q,LQI#NmGK0<-z>DE^x4b+OvgwXKyKoEW`@EZPagE*hhe-tLeL`-OM(_fe<ivS094Td[bfi7jv,`@rr", &
        "4W?Pbnl1U0Y1ECLTlo%<cBWN$Y`F59nT4$2)RmMEXp.G1?f>cVRd2HOcrQ8L@sRNYA?)aY9q6vj7+VZ$`(;DU?SLQTKDXb9GM%o=HGmt$JRk,mHuin@4kD", &
        ":Sd39=V].rn;k6/xF]Y-(y8wH`(Tf#nl()BfbyR>7/Kn_WSKgVBg.Y2C,?O%Az;9UZbfVXPzMO$xzLQa894Y2786/eBviudwJ4lI*[Asr9j_f]A`5^7mCF", &
        "U1b]/g,GRjsL5p.Oa;-<G-l[CorSGV#BI`97UzOh74swO/A$02Nz$BRDl[cidI<986JxU64SY.h9fu)m%h9e3#c;.rLco/jRx9*]JvOo1TAz:L/Y3OsFlw", &
        "9J/or58WRMdx.;6LTNHX2BiLYU>Og4I.+T#fe)AYRUnzG.)DniTuoWaPF[)fR7e;wue>qH5;f(^XHWI<hhe_hoyEJ%kk)6p8%4M*ng%O^xwE`r83PFvGl?", &
        "vQF_9egH19j])(jZx$/9ylM@o=DZ=W8`Xk^ep;<;QX-p@AF]6R2g3L8lEGMP:Iy$-tHp8H,B]xG>4,jR,0i7=:(Oc?>+)5Vh<rSPAkjv7+DoOMY#p+0ac2", &
        "wI3+:kqZ7^5#e6CSQ)X$MU<x)bI_f>E(Dr)FS@FvvQ+Xm=o4=?UW%X-yEnYr[.AzbDvyx>x84cy5Lwx4y/z,yy7:7v3_[b6a5B@;<ayP)pn6?B7cyij-*b", &
        "FQ3-<)zc>`$9Rs2AV?0yLJX$L;#.9-_`.=0iby+ONps,2K#di?NBk9#uC^/*m:8J[JV@9Z-Gb8ULDi>1emFn@b>(I<f6u4rOOkY);X;8WY;]e0A,u%Y0wX", &
        "oe6s44k#XCd7/.AIIGvT.QWNRv<3splfS=G*8ZqEXU6z]3^Q?@pFwO7hD.P7P%R=0>2wW1,n#h.H2=^dEHYnqkXGmM5u(c7VNAUT%5iN/R`hKpRZ*;Fjlt", &
        "yv0GM9J/Za^YsIk1zC^E<E/-7yQoQMHIi>CcNn?yU5RM#=x$A3LYw_PEdeCB>=fnslktB.J-g5p)(,sFv?1Ls+wP0#uO-PNd]J-;F8SzWtYuLHS/X<w>/>", &
        "[M71kOf@@0BTLPRZ/h,QJr>tIuD;k@xX[BT@+_rZMg)hBbC5ZLtwfP-/n?DOVD1h33XXOOX[AE*Eq#V4_aCYG)Df,P_rULYbn0BrVgZkH4Vb:PqC9sSv<;", &
        "Kv)hHqPy5D^V-G`i?]Dr@iHZy1JejTAO4P=aauzKXj@gw?0Xd2%73BH$;g-*)RZ<`Q:Y0kD$u8vq*l5i[JK`_RF0iql5n[9GE]T72oZHm*[YRKK%)SaL%`", &
        "kI`8nY)V@#,5Xe+0-^srwD[wLPXoGgZpJpzKX:l]7`T@_Bw)W7hW`;7>a8*BC6ge?yh25AqWmk(RBSp[/XQDnrW>7>+HJ8UbQf2>TA1n1%BeO>2L)Oe7_@", &
        "J67PC57Jc5Ksb;W7)BFcpg3yzj5<p(,0p`+Q.xmiSr,fC3m:)J2%*BsPzUq#Jnj,y(P_$D<DZ0^3)_VU(zI-pATuGi*<$Jp7BVZn:2(j9,_;r-K;nQoN3P", &
        "h^=3*]8I[5#;,82VK%hSTEak1I_*Ncxv.xdBfeq8[R4rxYH47k(@7u17p>IHf#co+q#rw.n7EB6yz%y[4x<X<Owe,pE/nzpICTde7Y]K9wqCF#md.t,M+K", &
        "DDzcg[z?%9RMUIf<-FzNI=+b<ND=r,JCZIhH=azh?+VHm0Fn97>,]6CG>_T.(tW,N4dCJYa^*<;ZIJrN48Bi+(>:,ohW#S$GqBo*=:yZNud^[:#JQG-<VS", &
        "AR1h_u(xZ/9:aa90.y/i3P>3<4j,l0*Pvz)gs0Wr`XhLr+.6tF?)1klN;TXpam#gWdgc.bO-(Sa%;hLUdd;<<`:TZ^VcoQJgJAmehw`@KfANLq7I(6VGHO", &
        "y`p6Q2p0%rgO3-7xDWAn09;sFl.)(?AF^OC>Vfs(bLs>eKsS7c%]4/4$<aCUa=K5^r<6M_?zD9_5?(oLDJhks3b#QX6fF.q;+xJ*7jhfZeyv/gXrxly,O=", &
        "e58`AR.;8<b8My>9ZVhRmtx--7m4l5=TTvxTf7b+224`FX/m5S0Z]pmQ;J28)W27<H-f8@;uEs#XL_kr$W2d?W2Y_L7mI@*^Jyp9*GBQTfC7$pb=fg:,KO", &
        "Pag?Xb[6oRKV0[%02SaIs>najjjd`v<d9=59j2NiD6>m59`/73wv9Ov/u7F9=S#QKK%<r(yqS61G=97HnuRduE5nZM-0Xt`9qc%#-q7ktbFg7.jt7_XZ^t", &
        "]rV^%`%Fq.7?3Pj-)W6bUKF^h5GZ3sP6EIQe2%t(dSw0;Qq#H*7yyXP12(zSq-OtXGStc,xHQ.S)ZJr*.>tKM$OGM_p1[cMW]XzXbSLWX.0FF0D79#-#iA", &
        ",b`NwUJQ#/%cIq;me+ckon[;RQO;U207%Jv_lz*ihpaqfRx#9B_hCRch#2=N7g4kzqJ[wEWD%w5)7+.4@nLes2IT`9/(D,CN4WF$Q.B]JT2sH7%=VYJs8J", &
        "F9-H:reQ,q;o;g,hBz>OnSE_*0qolB?enuy>ImPy4b)mAqI<u@Qz..HIa58:.g6*S>vq/ggPNlA^I;uMJ1F]M2P<q;AZ@^YX0np7u,R`XdFE#y(-cw:3Zn", &
        "df8Or/h61^uf3u_:ocUlhem9Xr8@E`W6DUta)eB<dH,E_:2c?`w$;u9-5L4SADJ.IpPtgmv_fjh@BYc9MhDyI8+q2l%kJ(rJY_-6RcS^s(vy(hNi$)NGQG", &
        "O[jgH]Lk8R*p3b3LXEmgefw[Pi-L_3?iem5/,4%MR%5Bwi,:8kJ$uR^unms0erw)@Lj.DU>3GvxGKwwjD];NMte,m7h#>Q8iFoo%[V$>(,uC<Z=pqbO7$i", &
        "qZ-cb;Lks0y%i$<Ch,X/p/ThNRW()/Z2)eQJWsgc3rIg075O?Pi.%WUaLY`NeJ[gMZ,kx4zDI=1FQe7d^C#U%<)JSPt6u>(v9,J%K1n2@(VZ5A@0U@+tCO", &
        "(NJdF[f(=gIJ<jxNJN2fD5;s`W1V:BVtFBN)fPsb@]I?,.Z<$@Hh78gUIF10WKb,hBHme=pf^6B3RTYK^D2Ak%$A^Dli3s/%+TUc?uRB@RDkKl>1wbaE0d", &
        "Z^(6+r%w`d+[?@uB6?0F8*:);T?bj_yk.6Yn%wTq=Xw*sWNlsi/NLXAf$zAe_VSD-OxQh]2<afJskgf(v1NM];GL:dH2xiB)Xw0xdgzcls^5pq_p*5T72J", &
        "5-@50M4>e[jfci/6x7<+LUAQ_gJX,NnMgJ;M=8`T/cq.TatW1y^jKL@La1mTRit(O4u/de.I^=CO1vnU,2.$$WfTw>k^r7z^-fTQ9P./K58uh]7C?i#1E^", &
        "-KI0dFaJIzqm4u)XT9fxdnIDTMRw#$M4%>Xo@-tK@16VkgS2[n38<g+hT8%[cIe@ZzeNu^z1ZI_$Hw*mTWG`^=z@u38z9TzP4j:io>D`$vZ1MPg*/9v8%(", &
        "B6$TlLiNfjFZA+8tjwe.0Jx3:ebs[M]A@@cFee595.qKs0%K@Izoa.25T?$G2.X:hetys_Jk%_X^0s=ez,YhChIw/Ni,*4f9F7V%XJdK7^$uwOg5?995LG", &
        "@oAZ2?1tm%[h9ulGVU9%QpB1wo$)XrZU>t$qaz+d$$(?kX6vt;]0ShmP=J1Y^$nNh9.):q^BPG?n*xPY`fU*Qte8h;P>5KIAGe*nGjKVSC.XlriMrF+4wU", &
        "Wu6F5?(`[k8w`bf9c@8Cmnl/]@Ci9#knLOLT+-(x@Z@XV;$`NsFhBKAkg_)JP3u0r2(u5t1(>@8XrDm5.ud6UX3PNQJ/cS^1/p4baCa/^Ih>#[oAjAXJ3D", &
        "]5QE1C7@AGuHE>6A3#6_fFL1xu-rFX%XYxS%x9/$,-Y^mRX?Ma/a7=+OSk0:^fVqn>1/zu8>v*7($fipnPj1laYTEz>CZk;LO%K<dMYbGQg[uz2p%(r)u4", &
        "H8IEhkD0ZzpJf@E0826<*IV$LKwG3p*9,->dpIN1(+770l2c1^FFiyr)Gh#H874OXkcYQfsoD<sF4l<mt6a4Vdzl/Roz5^q4l5fSVuIX(5VKi3R).A.%Cs", &
        ">5Y@910@Q(ql9FZf<-#K7[GHS)18++zXGeAmlL.ogk$.ab%fv9eyR/926MD+>LedID)4aMVAa5D-*P$6zx5NfC6e*k06unM:<u;+UxUY=O2#JI7jREnVWs", &
        "8*d)vz^z>qID0z[FI=Da?fU.mDSfCi:9_65kP=W]XT@y^PD+Y;[(pfu$%NiZb)t^7/lyg931czdZ/wR^0@^9G/TK*8Ub2-H^*Dy9;XwLvqZWn9:ge-^D)e", &
        "RpE<jGRP,Q0)m/E2KYDUO;P[4(ud#:7IVeu;yDPkt?f.%TlIRlNthPL60@#h4HxY@./pGj4C5T7wk*PvftW@KKAcHpJ]i^jMoB3HdB4I,0P%va8p=9R/`1", &
        "e`-ooLNNvj)sGE4u-T<6PBpA-R6)ONl?.y%+qs`O.FtJY8MjFb>Vn>i7yAjGF(YYC)nhw^nr78/Pbc`@4GvH`e/kvKQ,*X7+4-cYj@$1`1a?N;*z=j%OUn", &
        "U1;A:_z?]#)t`04C)/u4T@KVzUb:YTs[#n?B+o-(m8P1d$xk*yA4@b^fxvZiECpEoGR9kN8CFBG+#h-X(WN;8-PwXQW;dppt7GPm1tJ_(nAiCsdrR?@@6M", &
        "Wb+/Rlm]#j)3QnB<I(k9fPMgCupsRaQd%`sR#T@hv@Dl(;hf;+ccu//`T4^w_Zbh$$./B$zX,5eqc8o0?O4(ViW+*Iwlz:`zQu/CeoY`mIlCaGI/y69iMw", &
        "?nCh)<=N,oMd`>45k`JQR2GH-CQTdeZW4=(7H16j`1eQ.aMl-P^[Riy-SbQy@NxiOH>z,r*(xr/j1iBfbmfy6re(dohcmSh40KG*f1:X8LQym?5cqKx<>?", &
        "$B6uyA6jrw;SKfPVqdB/K2g(>^]+2,@CS6j=f9jkaNn)QhgiZ]ydVEp%)].IuJT.(ay,h*R6(p[tzCNSBz79:OUqQHIVs$Jz+>^tEScuzZY6O3*(?`_-`>", &
        "8C=D)l.Vh^8`a%ED0/>(TxpW%f`G72]Zd`()2`%>8?gt(1ZSnG#,ZArIOLKJdO%,9S5B+RR`9B0*.%=<.#m.Egc>W0bcd/8n7]2No0og,a(D5m2+DJxUFn", &
        "KcUa4,T32Xao9_i.wBAQ).,JH/aCx#ko-o@:#+NVhPkQ[a)Dt@q7;/eZ0)?n9+.$Bbys?;i(K0$O7Ic<LK>8HkO>;1_+8Hk3-sV9ZkdT;lwBN0d0%kHVz-", &
        "D@EBSlHV]?($k6.^q^a51%dDZLAHkB,G1M7$9<FIi6^`2jT.]PZy8H8)SU;a]jrH)(I`3M:VbbW9Amd-H`+_8,b2x%Y]+L5x**f%lJ<Ejjl3cEC2D%3I>?", &
        "C$hfL9r)71HOWN6(9[G*$;#_$Y9g=;Ghgc%AaPh?=GcKe,BF6--5_)3Uex+VPP@R;XH+8wbsfaeG2FQDg0;LRPQ`+^7*`LeuLhOE2u;+iF:uTC3>FGd%Fp", &
        "mRkn-`4S8HlwgD-y.?VeT<ynbwWd`TtGP4z%kj2/Ck*cZa/cs<N]yJI@-lHj`LR2E1tu=L?H*Foz3UI$Q45oPwH=j,=GfQJRwrGne6iG%U?q(lkE;-DG2q", &
        "Z2^53eJKUv.z8V4tP)YSK$M7ZPC+^9-05P1-Ymk)+)wD>3D?%rh<1253@Xo,?BHVS+XTj/u*yAU>7rRgb2irJ1EQzi^=Hr/VJ$UCBqncz>>Z>$jL#s3.C>", &
        "DkAbohMpacmb3mN]Ejw>1^0b8p]dp^=e5:[ig$gIE.IlMJTNk7XG5WZm*v_K5j2TN+<5o#yfIwWg@rFIBWY$y/x:(]<M4Rd:r7Ja(Zw@T=8#cFT;LCF)JO", &
        "J0G,/=_6QLJT9F6R1H56([->J4b15)$J1.E<p1uM3(t<TOE+VZ3l][*2y:?>@[j<Y5ryILymx8NkA#<Km]8(Kkbp5kz/yuR-lVI)$FC`?<=s_mVyM#d^ct", &
        ";O=dVu4h,*W>JFyodmOLxDxTo;NT_N6QmIh+h-UHuOgc<dLVQQl?R[B-%alYQ?M9cFmax-8Lz07MbXlK]XO#3Y)X4lvRmH5yo:4x[dpVf(uREN?)Q;W.si", &
        "tj@uL.Ys:H>U[Gu-6+3AN-tts$?y4NAVs$xim1^eE=rf].=2c?j)QO_-Ysh?TD8wCOs-I,N$eZ8RC$-)R;zt^bq0LJsI]GgooF$Z?u[%6O(#0ZsEVRx@Am", &
        "al-5AJJBzr[=3NW]HcVe@%,]Ps8v?5%]dRP#]H?^CicSl_hATTP38C^7*Py4c,>g7lxG-[d8`@TjM,e]b3MY1K#Tp6I44*%QP?31Nkwizi4pQgQWbqE/J#", &
        "RR*_G3joGYDahjGIQE091Gl`,)*OdL55)BCcOH4?[<Vdw@H%Nob6M$kvZX9*nO):z[Teqvc.efC)RAej`I^t=@/s<3uY]mgTSpo<4]3K)M[*qUnTJLsa6h", &
        "vSia5bx02hKa_j2DXWsb8vEB6aB%J;F#0XGK7?c_mZF1,ru`fB0@al5/GxEfGM`(,F.K3#t_(yWcj>w-k*?v;I@JaBzRZyl6V.]SoIo6U1a,vjH[Hn>@;q", &
        "Zsa,6dTk20yYyn;+aVttQoI4Zdg]IZ>I@52WDW)+btXJyU0VB*;,pB4sWpmCsQ;#-Hw+#/yD*2^qtRMcW.;9AG#c_E[C8.,%d86*liFh]YO.(c,)e=?.rl", &
        "IU_RnoJx^M0V-R7SA^,uPs<,R6Y^:<)=ce2H^iE?u8Eg]$$JKH0P3e7,ugfLl8mO%DVY0I+uQ:b*cJ5$`6/E-^jTXv(0x[2pq[tlDXZg9rQ%4%FE..$)7B", &
        "lkz$vl6+d3RQngKh0+RS+1vbbPhLE/)be9?$D=?yZ^>4hj<VO]^5DS7PzMxR/6S_E4zCj(H,6r#IjZDM]N99mHMK^SG<),;3<:oK*BbH5>X)CWD.8ma:5D", &
        "q><aU%b>f]>JLprj0TN#YN_04xxT9g^MUa.:ah7^MxEc+wv<V`R=>/D9KCGhYzVF_[80bZeyMUXElq`J*f.E%swR+6eo6,s)9TXuIuC>4R-q@kDd/ErQZ)", &
        "Dv`$.,h07mC(%u<?dxv8U;6(Hd9@aSm#Mf;BQ#PT-z>NW7h-aiDr6TbcIIA^4%l)I@VQg`Iv^p6nRN`ueRylF%p_Rg1-iq,T-_Q(d2]-TqS4<4L>hV<>pl", &
        "AS0i=[-h3KWSEfWx$O`Km)lN*@)KmbcdB$GHTOb[](>E(9XYfdX-DYIJ9]GueS?RrT(A9Q:CG5n.3p=CYDHSv^::Yhk>R30]6kuKr:yeazs5bc38uqN.Ge", &
        "D9saj8dY>5-4MouZQWP:k8)SIRI1kWsG.7/_o.frm=8heSz.=9Lxh+9`s3IX%nQ6g4+tO_Nh0Hbxmb`xdY,=<lN+-fVrJ5t)0G3E?(mnTe*MF_E3+%hOf)", &
        "_:OxPcDXCV0s/zHGn%,s8Wpc_XugkInZ.yOD34S/`VQtUJQez9tF3/H3j[nF7*pq380G8ZEvl5)^4)qOSXcQx0^^[c:F=F#N$zV[*iP8^:y1Lcmy]#<Xxo", &
        ".K4VxY+/>+C^(yuOt-*+.Juiy:tFLb3Z;BY;1p=R^^lOUO>t(H@O`.f8PCr*nghgwRJ*jhR>7-I1R3%.UV/0^k_T#tJ7:5W_N;l^#p2Cdh3gxwkTZQ@WvA", &
        ")s`sY9%P/TL+=vHHj_ZPFHSt/olYi3V4gO>zU5j9.U@^hy:_S#]A=49Y(VoB2CGXXt2H+)C3J:E2*I6E%y;FhMfzw;YzkRX_5HNJbWyD?E]YoIU(o,U$=p", &
        "E+Pek$n</sug6T7^E^_qkkxXs_5-i>>)P9oK)ecrW)IEA%:s[Hj9kS:5;.feq8E*U5?$)w85S02,2)$X#mpVgae<kpeDI?v%ByCE@;5RWr#=00qgi,VmQ0", &
        "4D(Nxpo(#(n4<T,%mVL4[/c]B@x:`8YZSddrwibI+XMb,^PLX:+uB#@V[P$Bp8+u%:FfwSfE_0?t2rZroSv?t?HWpHp7ei<G/#Ysk=W)oC5cI4zHmvD-Ol", &
        "TAPIW)<FWh;h]#wH22z/%>$/VnaRe-ue=dG$zevL,J,dJ:5Y0.OcEs?0WH=`p3A9n7GwJT<KK^Iw1D=:h]I([8Ob9=B#)A(if`BKHIo1he^b=ZI*H3j0Ix", &
        "Glf9mgOi$R7JY-ruN5V9rk-,x,(nN5oFQrB.xw[@Jv_3?-Zl@I`@S,jLA1Xl?,J6kxW$)0Gp;odDikmB$`Yu]+$<ZqzyN-GW<((%2WgNAB(kNFo?NoP#K)", &
        "(7pPHX43c;RrwY[k;YcwbOoxAa6(l7LEQz%;#XIUaU$v,lJk;JB;cBJ8ffkqqf8TVzvdM9>NnScx@M@OP)C+)Q/VWcfR-qsmF%l2sGB1$S-Wa>Fz^;Efa4", &
        "zl?r#.^4rUXc+sLBSv?db7v_oEpZyy-7E()Hm6,]xS(l*B0R4JaS9Q2TI)m<n-w+4S4C(e/Dob^3j8BU4lu4-d]+<_0M[h4/UGhyyubvbV5`z0CRjGGS<Z", &
        "kw2W(Rc-/GziGgu+yV/zpj*D[@$L/#yyFW+K;MY9?lu,NOz`_EFldZgVRIun+d3-D/4+;aZ/mm-SfnnZ-1,M<GOpi/qRo*2d;GP?_<t`wI;DdlX4),eH;f", &
        "*i8pbY#ZRfpFs63YNdE`^n0cq/.d)5FX(L84thU5*@=u-/T=-j+v8ClMO)vE%HS7*6#-kx*j^`rD>=z]OChuJ,LYN6Cr/DiDCPiX/H29aO_v;kJ]C5;YlE", &
        "yq...;iPn0TB#koS@VeC$gnL3Hucr<0lAj<B8n`[4J:0.x>cn;2PLk2l_gi,tK?%(#TG#^LTLdNKcsTn6dp#%@LiCM?3HmG_qdD]yo4yuU=4]DD:%k:ig%", &
        "Sm4^wWR*FMhDX7E-beCBu+,+cprcUn,vALH_KLBgW]N?sFcmGM3eX8s/3Nouj2Gsla?BDih7>muj6v8lbzm+r>1P$c-HM`>XwY@*S3uMn,vALH_KKz$S*I", &
        "duq^KY<4BBNw(J8I9G`Aqrj)(Jklx?Bx%+Tb%tW6#N82SPBYWSO3Z(A9<.4lx4:.7VkDfxE6wh+N(7%0_gSW/io<g*7fG[9?36KnaGbNtq+I)<=GsOp+uH", &
        "Hse(R-W9nFSNvOX2EUE4hbksM[ecQIqhGP+Gr5nd^$*:CG1tDRuSR+Z:ak(6Fg2EKj7HNesg?t:HSjn%u?MX.-qdMlEL,+0^HyYf<;2P4L)zaO$Q+YXgvp"]

    character(len=118), parameter :: BLOB_ROWS_13(100) = [character(len=118) :: &
        ",eD>g,0JQJ3/GCyOe<KNQRN@rp86)0SBRX<*L[>@,eD>gP54V?%*pt20_uTW,Zq:rOe#[?_D8,BN$bLp+NVtw)55BScZKT=Y#@beS#g_@q_NR<wL%s(F^W", &
        "Y.[3>?>E>k66fU-GlQ.@uo*/W?:/sClg0@U^3$jIJSP*xcT,EcgF*p<>zMxdKph>$i6<vL+vT,eeLF9swN;KWyq:C3ol<2yWG-MT?wE2XucjKQ)foZ,_Ls", &
        "9x2_cR3k:a*tZi1@mA2*>a]kSn>+$w%CL(+Yg4WN8z6j<Dzc[Cy+Gx*k6iGX@-HIDzgYDv>?Yi[?%jEiNU^S@$+An/7iY#-,shHDh)CH208NOx#wNo[fbT", &
        "IPK=*2$FhcHn0CLNA;NpQ9:vH:<G[V5...;iPnJW^7#tL%w;7oo4eVa^bT@P[%ondTcXpR_0j:AsQlU=[YQsw$w6tSI[NUva.9nwW*W0q`NaQIsChAD*w%", &
        "h^#0Bu3eIIJ+4/nO-Yn(`m0t6y)GdzAj^s_$gQ0MHv9s#-h7V%xZ=*3hVV<h9*isjo*[62KKLP/,lR4-rKPXwQV9_)p)AuF8ZA@/c1i:bedSQ#*Z*+qlZH", &
        "XzpIOOyQ@K/ef<8Tv9`(1?(g+C3]dL4f+p%(c*9%jmC4of%WvUq[-yGcIEag1E4JGJ89/R,x`AJQS1>rf0G3@fD.BDWvis,q/An?e.V8)t9:BM50m1Qaaf", &
        "+Jflr$c1,1z]0B=sSrRS[<W%^#Dr7h[Vl062r<LX%Ej<Vi/O5sW[#iyWiOo=/;2byd;gb4=W1E;MJbcevw>z^:MsQfI>+<d)+e1pQFCHidt%u/WUV6OI_J", &
        "t=y2a4(u.uyXBD$Z3]P)z@XDm(h[l36aWog+_OQ)z#H;(0p5s)_otjS`?L</i0=L/4g<B*BZzjf68^#uoyQ4I8i^jYYH#_f6F;Rsn3BCTgq:,)P>HzfAn`", &
        "oYiSEmv(LYUM7Og-/#GTTM_baj0ROFZbXQsTuna)Hu(n6+s7BoA*.WU]n[N/3dd<x5G*#N.iZs]E-.b9#o8J@i3(sk;9;sIbfOP6*%oG2Z9`k:M%WHf,.$", &
        "WmzSG+9c<?KZ_sj>-/vJ#R59#k/.wCIGX<*zi;Mi$15bFS;z*,8J@4h`my72Tza`HhLWpA#I?76yqw#U;CdWga29wDVpU72PVfpo#K`BXZjqfTjpoHDL/n", &
        "MgO8UwD`vSSxYnTQN#Oa/%x)Z0Ovltfz[FHm1+)qLV5T_.qLp[#+Go^3?^00h[P3//lNmp.w0D2>qQEvF[pelfwak)>+a@+f2RvK;</rtb#OxE4hQ-GD>0", &
        ",K.]OtZ;%P]$]TwR5k*5s=M#Tjcv8<gjP4pY8Etc[/o7RYaE2L`H77/ILu(4lvbSLku9+T_Nj;(Mu;<=K#RFSXd*=3f+n@J1kCQ?XfpH>DJ.CNf*>6g3=X", &
        ")W?z#WFMAPA@eNk:(nB8DgES0]pN(IbMIPPVsYTK%D9*s55x9.=9;lRkpXfSC$EVkr$$hkO4Arj)ANnJW]OQ;zaS$ETdh<8jGBR)ky@HPTJ=ucAVO*iUKV", &
        "D.=h4J]aWt4VEpSqSg^?_w_5hqv.Uj-U4UYhlo8=i=cLhSpJ[LR+lpfkZ-K.O8YH`c8W)4hbmS@`SFIXimp<GU[6`qx?jfqJPUQ+MVpGdnIWO_(qU,,pSZ", &
        "PF#1+nG3[=TJZj+@wBD>rIpRv,`bw=pl_T4U]v6T#ko)oG*yF(;;-l73QLjnPnh-1$#,Vope6.@]_;)bz+yFxiAPo2ul]tWSj4BR4W*Q$>*l9Gl8z%p`jK", &
        "l3Y?qo2rYJP^Mfl[Q6?=?4S<Q%0Zy0iB4^>etA$;oJ+?$%cmLL,6<h-@J.bF9yk0ZEhWbfl3ZK:S3R<AM%hZcFt#4f8Y+Wm-cIHW;3j>$^u;X8O9$BvLUR", &
        "jIq7L3y4Q40BU#P:1aar0jsoBk2XNrXrZ=(7gl8Ekc=JZ(4[xu`Qh9yMKSwDhw#SWrN3pA5pSJ73?)vq5gOHr]gID`TVm`4z1:$/AW7`dsC,-Oy++M3KCb", &
        "[#.WsWlPL<U``2TH(n1b1Zfqli.7RbBXk5o>`iB*q-Kzf-VFYvm##jB^xg,DgkTdq@Xj67u@q=BWSUVifTBGb9qoDDT9kCTIkonf#PEj#.S))Q`lD]3c;M", &
        ")EdI*vOWv>)d2Hk93RBqMcJjJ6$v;Fc7IIf7K%rvx(WQrJ.)9[1VgOKMgaW;M>vLc5Fq4bI%g.f<dCQ8Rp3ksnlHp:DJe)SnLO-mvRNmoc=@Be`^b0d=4$", &
        "@CIH9J1<Vx.t5.qQCOlJ$O2GUCUhvzPF0]xj;d_(uYmTjnfD7,YCEBWc]qt(e:=lh8`7B`pnsYgoap?ltp[(rVS5G%5m)rmUQ+A*j;2:5VEOghE@v8x=^I", &
        "OT$:KlqJdw/qWmo`wSZ:oK3Ee:6yjDs>LOnUb[K(e(HOZ2]]6ld<B+zV7@;b,:[4sLx;5WKz#Cg7-I<NIa#fy:d,LKO%s<1>hSwrAA9XzA]?j;1:X[(HM`", &
        "^SO+Q4>LO,:Y7tsz/3d2Bbo%00t8rUvqn)6_K>4)W-<a+M7#6akURTlH[]min=eD[U^Q:H-P(N/$4aab^DH8y3E]yYRWO@59UC,r*d1/]@2dJ@$isC+^b8", &
        "I1cqJzzfG]ngJP1DAAy+z7y*^g<+PE@Z+AGbV6Tt0IKo,OXpBkI4P#%g,RIl(<K7ZVfTn=9gBO3Cqtg@_aTPbqs7]=M;8^o/MkFd02;kUFfIykx?cY`cJ;", &
        "sW4nUoj58xR#qV[jUuTeN)hL2v6fg,OPA7BIrmzKk40b^*mE_`M_..3:%O`NtRxIh*)BE@JfW0vb(Zcawsnorx]KfZ5Nfz5NE*;d$O9$MMIboRhPU+6BoJ", &
        "-`BkWz)]1O3Ie%l[yrnXm-S]P%U_%Qj^L[Q6:gUz^E9v$bd+5wh<w>2R9I/z+=64X@.sSrw`yqnFkr[7%XUpX?)ZNxu150GB]:HEJZmw>Trjw^zmOiHA`#", &
        "OG=W7G%Fsjie+@*OF2hWG%Y)lj*FI+OF2hWCaku[?`8U0*#DmWqnY.lar5>bv*zYZiPW*S0ceB_S[KTd1m.-7YMj^TKo0J3nZ0HBj9oI0vPT[#9#IFsQZ5", &
        "#7>g_?lSZlHC`_7q/(A8k#^e6,lW@+Xdi5?Ew)q%(^Wa.oi8<nahnYvrtT20GVrK]yA/.kU$;?q^v8@c[(/#eT$;?v6Kw%uRcM%z6[U03.<Ha(SjfYFGpB", &
        "[U0NY-vjuSwg1YRg=(%lT%Dy:=dg-2zvJ_bTV1PL:MOyLvremNlZjwo?ut`oNw#N^(6%b<)_n-TdM8`us8i.$EZMsfC9bDfb;opBpWKsS,]VQ262qJnj$e", &
        "r*RPt^/W*HL1#3)LJTN#_8n2cX/ec%J:#`PxW@)@IKux0f]9aeFqp-:#hUQiZ,J@3(oe]eQIbu#boN9SG^HRaW^];HybW$@xBf=9fg7qO)oIo$Ef`k`)CT", &
        "J;8D%?yzKrFPtaPT@E3*P:USrI]-/YfM99$dZu;UryTS1EZmQ>,UVC@6=DT]Alf.v:=GbBY9G7h`xI;1+$g<DJBIT%09ZW@MPvaOQ7D2rz#b1sIqt<`A3F", &
        "SKGurY-0-AU4mA@avoYUOC8sZ(c/.muXu(#Y.m74soV9Kf]%yv?o(H^7Catw2S*rs:#qRo=uE+0OOdw3*Do+_^L+_5fwyiq)o^67Bevnem-UmM0+(#q0`7", &
        "^m<PU/`h>T@yBefX`+vzOnTIq%C<a4dNSKGusi5d`<(RDEuGsdcp/W)x;OzpZIN,du>%g;#7fb3sd10/u2q/`h4.*_Pl9UKg(cj]J@##ePTnpg_yPrE8Hf", &
        "W><hW7FNT##09:)16j(#-AYb4Vx2s,+svC##Q=S9UGlI33;3f#$(V,N0k]nABDsX#%,24###:=34DkUsKnWPM%z6J#hZ;1fT`)7P[OQw$U:QNSmcwI*#Cs", &
        "r(0P)C0Gkgm/#cli+DSgG<*TF5nYXBE#$(NQPIm@P>.5db#%+y)>2K=fW7FMH#)2w..4,$$721jk#2W6j.hb1X.`pN[FAMuH%nQT<I#P[@$xWUtdzP[I*Q", &
        "1K+7C3%V+;a/,#9c/`Q0%)R#%YV1oJD9A+<$4h)W(P#W0Tv^#)2w1>-t<t#F=v@##%g)+vD=,##;.;/=6I(1*_cn0GkyFHyyPY,j#?jL0Kh`#)2e3###BE", &
        "Dm]ZFN0nAH0UMk]O%ZJ9;k[S^wc`$m1e-jy.4,$=Q<30)#/CSretim)##*Qk<0w[?$hhAyR[=-Aw3cr^>,*-87C3%%HyyPY#@1Lj6yO2D:DZ5?DmOc]FeS", &
        "$khTZg=Q`[*Y(7#i5w,r)ADT[K?N/i;M6FOmCq>#qm;]fpC8[s@JN-2w/9Y,QBg3J7`ETvvBE5/3b]EEe+5=,-cEU$(:cUoA-+DM,h1k[%sX>@n%1kZqp)", &
        "iSd8SiCGWILjw$-5KvG;.;z,1k[%vN8FLM5ByMhn?GB<E.zWkX<aQ41k[%vN82SPBYWSO3Z(A9<.4lx4:.7XnuA-W+Gm51Oe$ve^V*pbw8ob^ldov%uH7]", &
        "gI>EZb2n<mnSn+NoFk9=-bzaozh]6#6^EUmCYyDQs,9(@X%cA)F%_*N:%,x1>-fB>S*B/^18ZLSI^NCheCa,IMHG7]QQ7D]outMonLxof#Cq=>BnwXsW$u", &
        ";+s(oOPhucl.]-z65:GXor#d8tS@B9#?XMVh,49=ohjF`P]$3[9YpUntQG/X-XE;@%bBqv=TQA>GlblcABIAC>rn^Wk^871L]^B?#k.uS9ovjoFGnj*YI,", &
        "rnig3C8?)ROcWh1H:3Lj]WnurS7z9aSR1(B;]3vJN8C3u<MTT:.%<FVI,q#RQ_/_J/FgtV<P3Gz71=M:pqX0J7b[sc=cv=Bj.1v_#+7IBiPB]3u8QX6h=t", &
        "[H5hiut.CRVY/Fi*kpn[fU7,+Mw>WaD`#=obG<6N3^l,4yj8=8YQPMf9AY^::W(Y/2gYe,:whSU$P9.2BqWiunvJJza>8jZ]>_laLiFUWpm7c+389iYQ(S", &
        "H*el8CB[zwC._u$:ksXpq])7S4l#$,9-d>)5aN8PMabsumBUYtVW4:jglUNN*:,7SR:@6riIJNp9C_NkhgitwBS^4iF8NJE?7@@ufz0l;aCQ/(ncyc8<e7", &
        "$tW0Wkw]#zvAyq(^/LSv[#V`p;YcO`7:218:SHT8s_js>mSBM+<-Byb-)_g<>S=oerm-+nhgN[@Av4;=TSR;4Dw%uN6*_B-(:RC=Rsv`3i9%JoawC-%-c9", &
        "xtyFIv+fvIcgu.rb:[B)%ajSH$7@9[Z+$vIZJJ5pZWEwC4KxS,_5l3RWoOpqz[25bxR/s$cAj-CN;uwkGiz<(m-H,<.NiYe+/Vhoq/PcMWe4-CONbXGib1", &
        "/)T%UYcP+A#VdHYSH$pm_jyS>Xw`bq-,wYJ^gl>e<M:Py;p,s>9mkSoE9KZMfy#y3,M:YgW+M/#Zfuisn*Nk.B:0bH$JvNJ9Z@)z9.2Cypr#j):ibdBZjy", &
        "c=TFgF*qX9.D1Fn/@7zcr$PceP2YcP:$FwHvD77z,gwffS>*e2=B-yAgZk[EZ]Oerw5(rdS4gG,P>c]4tPA,d$U5rlrM_>,n_eeo9+n-JR9#itWt:I73i9", &
        "]YG]vIU55w/=E-=>Nd5jN7Rz**^];HFt0u%Q#:C>-+_u(,pHWLe#52sgimA<*4V#w[q(H*S$B/YcP@.#,b^>QB6Jrh=wD*8g9#b*ckWRCU(x#23g+r9.2D", &
        "4#)vv30O.$B8Ep<%2QW)cFeQ3-QRNM9fQc[=<?,0BM7?dK#.hGn[Akq/nGFAF/H8n2*154Niyq/kDS/YI5qxPctVYj2#)tV7e+nFB?@G;,nTdr^@YcE7iw", &
        "hnM?*0:CJ2%T]BRq1BTS^C%%9=w;7]Kd%%SVAuiiM3-._w4d1(Eq-=^y>S5RNRyx%$@b9IH;bnZj8in(*g],)i*rcb8CZ<0wZn##-o_##HLjkB)Dk<74%#", &
        "#####So=$9HztXcGbJK=iOif8YbG4z0K`r6S#JUYStvO.Q`-g**%=WE###Po5xZqx###/wd#,;ltVYlH##5HwJ[c^f#(./v.Gc%srQE:3nP0t8eV>oc/P2", &
        "wH8AGbvYj-Hi)Fa;(OxL-2#(<d:V4EbdUnOY2pdOOrM7?eMiOK,=utNMv5U+$k%#[sL73<_wQ3X4yF-8hW#c?fwF6T09S=2^0SC5NC/)V4stVXS=KlCk0<", &
        "IBmk<1+h*dc%oa0`z4IBA`.KiV_/l[m6-raNl$@<Lx#LS9dshsI2H7iOV%Z/DqRKYa++y9B9?dHpt9o7c_]:NWjfg*hgJff[1Kg.$n:ESuR;t%uA]ABD9j", &
        "bN2cod;oR/J$Jv.JNp23A<4>E@l)=m@$J5zPf[1K_/=_x8SuR;t%P[ifwC/[7.d2Nw;oR)I#CSh[Nr=RitVYq><2psrSnaX.f[,ts<#84(SuR;_/FxCH$J", &
        "v.)Y]$7Gd*wq$pqaJ$Kpxa;*%=P70OWw/<IBi?#(kWlSDbW>9.2E>pqS.Ysn;v]7Cx0D%pG<0*o`hVYcQ9B,r$x.h>ndEtG>G`BmOssBTi:Zv%IZhP[tGK", &
        "wLMMEwC0,K[T^nx(_z4N%O>],,-L:/Cp<2U9.2ERpqw>09H51)bP<FdfXQS,*i[s2;BP/1)zX=J##H9ymP;#ZsU_)t#2;rUkB[<,2yDY$*%=W`vIT?9s0R", &
        "Jmw8FrAv>ctTpqHsxiOIaSS<t>Y]u?uw#Z+X>maL5qut]pDN1%5OHzYVU#?Rb)eMN#bNX-b)##-o_%P[WUw<uM<>=+Fyo4=czd7/x#J]25lGf(2HPXj>(k", &
        "U)sy0D21c_u4bX9gL1rH-?bZU.EbIlqN*i0q(MH9PZvfN81$PYc1f4<2pMS:^JJl#[SHK_LpHc6W6L6IZkV4brN83b<^FYVll@RWhm.)4e71n+9bd:37[s", &
        "b*i<5s=L/,EpWx@Z0VSEzV(t--B^lxS/]c<a*/s950nLhKM`UC($#O(q<2^DBS@nh/#j1U%$/=pXq2*_:w^>Eg)goe%dGuMMOOkSCUS^CyMychhN*e2VXR", &
        "nI?awCfqNCSpBA9VK/PBvjl=a<QX-NoH(ibo(kk2$DH63Tjl*_PVG4Ix`@c?9TvZq7Jl1yvc-Kov<G*51bWLiy9hSBD^Ug-$-vvt8^eKUY?x8=E_zZkM@*", &
        "@)P5-AaPi3O^976Pxopi3q;.ar+F6P6H_Pt$7;Q=TlUwj+3Ba;.#LeDLX9[BOs6nzDGJw@+*$5a4%>v2XuGI<,$_yS+]oE-U-FT^M9(8JI.;pj2rnfE[%/", &
        "ZJ?QBT8#pVOdE_,VvB@pLYu_UnfB(gUIPu/7H(RXd[m^82nXuSGe6)8f@gwsia>g89vb3m<Cq94v89d7e63E+Gg3_9f/.q.(JRy/Qm=2`_ceN^P/@%rfFm", &
        "lA(4cmQ^C+[z>C#LrQiM+x2ho$zaz3BaiwtZJ-p4S^GSFRWz:^L1wE(oO]32EY%,Th@Y6PD#WjE]Eax[X,jD,-7rdU9EQcoqVOo$pM-.DTGr>=GO$I=U[#", &
        "/4R3$*d?Or<5Ocqy<qJJkrmhHa$z>t/,jgg-cl?FI`+MU;FTEa4q,W7sa%%6#cBk6wV7x07iten`OjZb<CdP;tjk+9slK+q$g(_ZzgAczrHCcJV^?C:m3m", &
        "zJz`X]O9,4)=+lw%_#BF068NxdQ9Oa/8T4?87@O(3tB%k)n*dnV%[+j`.EV,J9b:Zly$dj*y,TVNI7jJ8;+Xt3gbv%r)R-QX9i+);(yiwW?fiocvii-E_d", &
        "^ngUomM:ul/T^CW=lMMa)<<#L$T=0tPMA#ZO8iW44XNYl8XKM?EMTO=q9?wbqeV.2+S$kap+V*hef-DY$^#/d2<2Kf:hGOU24YR[NY2X4l+bk.o@5uNM?d", &
        "HFE2@BXQl3zL):QFJ#4RDF#XR1=f3nt>_8t%wJxDXO]C=W-bpx(^DPHi*X^,BZHwlKC`QtJpbpAB4#-m++Jnu@Qbx[v)1q?:56.pl=9m/1mviasL(_Du,0", &
        "ga]DC1;Ih#x-$qV];:%8F/w.(X5TE)w0x1Z4zStbDPg:Th;WaIk,;26CB^AsXR*X8at4q(X58<[Hc@7pL#ph:Ve765jq9=F`K9SPwx$ce/D@?McWAm:`_j", &
        "$uj;R-,I+KcpbD^NHCd,2R-qD-2s_:[p-P-bMB2lnA,#erPiD*>c%JeB`vOH8gv;Ge_Oq@mA8V$PjC2X?jn.J5ZPf`pgXR<0PJDl,]5>v3A2Ah),b^OR+[", &
        "meTO6[pstie]CTYblf2YyGtJ1n7Bce^,DXYGMBO427q+O1Fw;Tf>c2HH2JbUo/:1wU?/kePhfpL/lCHe#0^RB0>1UML>4eyEm<VrI^<jD`]1R_c[n)%>yk", &
        "lIEuS4lcZQR6S0(P8%EO_q@5g$j+%%c(Aw8LK;3JvZvlcjpgy5Z/om^24kL+)1Zk/+[$*S?-](R5<Zb<YsHy=[ej[uFib7MTvSYleL;B1nr^p4IH;dPg4r", &
        "3xvBU%-=vrAn?g+8Y5o%d[jk4A3@;xEAbwDjOs;_N1#nJ,L+D>k,UBLj#-[i[@b0T,^G4+0ZC]/R,91w8*>uTd[FVDia,nXaZd:>YAaAsRHj,98M*<jdIZ", &
        "qZ[V292V#,-T^DGueq%^gB==B%yeINY79=NiMg_2`>Rpjfakjd5Qh2<x^p]`Iqh;B)j_X(@(LD+kEc*__y1K]1l0kOsbF%`B%YWBEq3LclNx+DTEVG+?9u", &
        "SUk+?m3QP-C(/;<lUzF0DebDU[>t0jeqCO>UB(0T/G5wv?*SM+dZ.%KO#rTb%>O%uX(^[P=;t?d]jRR=O_LOLn(e`aonR?9V_J>]xQn0ax+[P.dg>xqqE/", &
        "o4,NS<>pUc]il5N(FWmewj[=hL(TDFO?yRFbJd%m>l;w%vgf42XbhUG+,*E2NbAwyV8f4Y8j4Fc0cKB*/EZH;<?42wlGAhvq9]^i7=/)bO4oOY`CsEWx,Z", &
        "[g/,Fl-ds.3(btH#^Zba>t88Yo6S1/TgItAd_BS+fj(xVZMOj>`23FP3`HV9<9(BD(MKJR`[#>qXwdz88J79DEP]Fqae>RsGj+0zO*+?sZ([O]#K<pB=1L", &
        "8gCu7m,H@=wg,d>Ii(lpa#t#bLxGby3JsRfd=tm.VA35ePSTw$NU[,xdR)xqzMb^`d4*fh:f@j8`oOvC>jFu@@X96(quEBzVSHQWNOG-bNPu*x2x`mtQnD", &
        "-UQ0`-14j]Njy,Vdfi33zf_IPvM)tBCI>SdSjRqse-,%DBIK5l[]:?-)?s7NEB/$(=;O3GbzZi8@C4yZ2ey<:HF*rQHA3FVEogfCswRyefUgmgOE_0.ADO", &
        "R=ord#4Bdy5#jlbCiPUDz=/3Jy_h0Z8%]^.HOfNe5u<TH=3mn]LBO[?b*S;i@^r)R-SSQIkU/pboQS2i-2M.O<LhWZdUNf=-HGgp/lpBl1Qqx>layz=enP", &
        "yhXhCX-ILVLM;8assbJEent$j/GFD+a#K04R^/6JK?sOBmWQd0#s%EyeI$D2ky(QQNY)8c1UGC4k5=_9L=/6/TPH3-$dT)n#7z?XowHUAGBQcdVmWExv^T", &
        "r7KN6B+so?k4dm@Zq@X8o9-vj+Dyh=grN(pD+e11XR+Ec)X+II]EKfIX5%RC)3LrkLKf0Es^zmXLYGLd$90Ktse.rOVs1awrtRBn2<$xDF<ZNT*RwwVqV;", &
        ",N<;f<vilzo)RE%SYnxr7`iT_9DAcf_)*G;+u$A-y^4?_6*e[JCkeFI<)c(k4WGoDfPUofeI3$L19,5B5D$z*7z2<*t*gH8b=OuF4jO1mbz:r[-Y5gxl(-", &
        "[7y?PbDHX(r9Rm##by4bWE$7De(<)dp3w@Okw8:G-$#oe2uz;NB(5#3%)r5,fxM@hn[2<f10eDFS8jH?TsQZ)[dvse[LyeDTa7)CU$S6P.Lr53jYgx5Vnw", &
        "c70-pF.3DLxk,z8=teK8bh]ADXED[6=?]2S`Ui[MJPp<av`L<YbiPIqHjG8wD*GjU7SVQUMKp+k,#;b]^u_RH14SB_Ho0otGL/8_eP,4kcE5l5ZK3KfB5h", &
        "2vSJ,nvPgHA?LR9X?WffY^`joJn*MNCP8I^kYyC(BN3PgwMZ?$TZ1=-wpi-EuDXnSxgm_>#ON_ps:m)O-jS@q<AyuX8(R9VP^qHVnc*uY;D1$Xs]g^dYGw", &
        ":Kjye60dYLEQD(=@lR+O.pXzEd2P8KOOj;3#dKdvVd/lWqnrRYZ-;rtB+V#6^WPzA2R`.stm0,lXr.XmkiXlw[=$c]CBO`[DL1`A[i><DgWJwJNTwAia+N", &
        "2.5:.QJx06Q1i.CDa-QZ4ti/.6L/APtrVhe$pZoE#`b0CJNXu%Dnh-h_vPEYN2=*vXaD,A@L)LhW`9s-P:Exm[2:#jJ9.)1aKVB[VkVS;4[+/+-E#unzw4", &
        "fo.O=n(0i2Yl/6Vyq]L(@#.JuQ#9wckfsG^d68CtitggDH7]bP,n-0q_9%8(*)$DuT0S+ZmD#p(^hxO]9gX8^U/^+CA7f9jMBK+Z[8K:)?I4PA=-?)h*jq", &
        "1#.kU,V,L%sm-vVcTifLor;gIj?)MFN>t/Q8pc[pyTwxF5I7i[Y1a5x#5p][t)3zt#kiq98/xUZy$zZD-D=k`Qia5EdTfWWAeiT-@gyWWnET8SKVRcb<3_", &
        "?f^i5bt.C4rm8U.[yhs]QMu2D[6Pm5cUO,-ay?=),KkP,dwBR_>Po3hxO#kxThz[K32Jg6(<0>WO:uR1X,DP4xzeI*?UlP2vVy58XGO>Hz4LN_%dmOsga(", &
        "h-`nNv5,96XK9i5i62:DNFm>o42js]co?=[hTH>x,ParMY(`FNq^w6YaCRk(gHLPe(rs*u$v2RNCs%w]GWIXtPYM=P3crZM=basGX%rM/A$:^0_H:B43-t", &
        "$eEo#sA:zF>fd3R9jntET,EPlxG2Xtz:(7h4BQgg+B[HbAwlXP8:b.fW]6Wg*Ol->5.Tfo>svw5)8Jy99b?tflB[L#f5?Y^M4bI>HQ4rPD`m<U(oLFbxG?", &
        "S>pdqCP@SL$#5al:hiRTYOy_Ja7IKm`p;aqqp3*P3>>+:NL[v^-E,)<c.sw:=BI,8w613Xshb9*=6:2(U@qaMWBrD*pNNf#v:_;lvi_9Iy=]qkweP-SO%L", &
        ".tx[Z%O[[:>kHs_L=6py^+dUs8`*od`5gF,G-`QW$?e5IV`HCV5ZDvt#=KomE?lXmd66m5UDf***oygdZfWCr:3Rf63kRR)u07pM4KhBWorh:y,Vde3E#?", &
        "AaCjjG#(9h=_DOj4*[H>cru8kxT4Kosv?+Xomn]EKeF=gcOnXlVC$r5gOS`@FzZ(W7md#-uvGEb-+s[is<WeQR6X@t;?k$7H5foAiop-(?@e>i+(.b[%.7", &
        "mZCk?9Z/XhaE?r#Cx:i?-,dZQCsnDuO[d<.i8O]NH[Wn-:U/ry8GpAHUb#L.Z?#nDZn@JLpf3OVq^MyMU7RZb2@2az,-bj-k.Uxf[f*m1ioDiuT,lp+B`^", &
        "mrUNKh-I@DT_SkHTcif-6hP,2Cq^dj=SEbc/8[2HR*,Pf;_%[u_TI4k=j4S=?GPv?)EMGB_jVIcia+MsmF^^_q.>v8BQAwK]+dYA2-+N[ts^HWd8@QCiqY", &
        "-H03AG@^cKK<oOH(H,fAd[z<SQ^80@l_:;QjK;^Kl)NG,q]nbNEB?p@Ca-Wc<^y+#8shQ`^:;e+hE6o3?a=pN^(?^lfE*ke-r4qJy_j9=/:)V1F@lR(V4[", &
        "J+N$cLidbLLZ3Dv?2>KVo>gaDV4AO[Rf:VYy,g[]ag^u(I?.3DB3-rIIP:9^Cd[,[,4RB=deH*M/OuINp*SMpMY(I)$4SE1EkwWHF[ITqOA6o>wu=ttOjx", &
        "O+JRjXy%_s=;DbQmtvC^*aLB(`p62QsT4en=CHDFJND2;y=gA?OngFyaivjz/JBE6295>Lk-_O)ftU2;4KJw-3.0D`BFZB_1=v)kluMePShA@+9PGN9f>>"]

    character(len=118), parameter :: BLOB_ROWS_14(100) = [character(len=118) :: &
        ";*V7%g(F:2i1zH7cKJoc2#zeb)myo8$^>-vi2,@+>gsJsD-x9^dfALle^49(GtRuY3P`BE]A01wjq)f/N5v$1?T-<hLhPeQ/vbopH+Q@aJT<H$(oHv8-Ja", &
        "puE,Oev+MhxWZ,,IDh]ZC6;;MZh%LjK2p4`s5d3L`HP9,j*`gXzDZJ*,u3BfZduTdW(eXAZ6[J<.<fN4;e^?:xovL#z7EZKoK,.tW$1Fu7@pLHAP^04-K,", &
        "C#Yw+]^daC4f,%=aMZsuH4)fNDQdK`ec0,,x>YzV./7)Y;9V:2#[7xl#,f-w]/t(-3.0aeg_TsdKek7q97B/W,:2O:P)GS_DwdH35ihKB?406BePo:/?IL", &
        "AGy3sV]GO-=7%ccetuEIEv9mB*>iN2vR*O=.^YB9:#]]gQ4g35q8sb_RZ<2Ktnm=whcsK5N4#pXk:UX2wg5$DS=2C;]l[z`Cc8qKQqNtqzUBMM8AB80>,P", &
        "+QK6+WCUKip]hMSw,VR#?EJXlKC[eDiky,`-`)ijgTV^gi*23OKnKgfOnT1QKeEnybUn.qvvFNx;nH`OM:BmhiVb3$x)L,3lREJ1h*l`2X4M=3bIWFp<ts", &
        "Thv7hIQ;5XBv@f^g)p@v8aJ2Vn#Z24=T6>0Z@2Jl(x=YPE5I8ob]Kb^O.DZRN[0qp(9@mWSCLEW5P8JR_ThYRHe0Qv`Xq^92B*iB.aern4h@1B$#wMQ5-;", &
        "e:GQI)t2ZndcQPz-,6m[hfa#mw0idlCa_Zx0qmNlzt3(pgGU8WvB2`wd_7HI7QlE7/fAD]*SS$S+ZeJcA71bJtempoc]fvU;)Uset^Z/o@f<G=4YD-Bg;[", &
        "GlcHLVQj#59+6H%51Wl,QxBInKsygJnZFZ_O7mYk$g=(sx^wqG%6xSN4qW7##0K4E5Ux7Ti)zLUnSC(.vEHX1,LqWAtej.I_ZV>6D]VCKpIZbCz$Kw@?8-", &
        "s]JPA>`v*9dFJOWT5ISqJ9(bN566a4[OfXf6NxJ0_3Cm#X<xQTO@o9e,@6g2NG>FL%=4Lb])Ci?8Ft^*H@Xd/x8bKvG+Ntr=Itg1[=+VWwWls>aYub65C3", &
        "lYMWwU2hXKzZO2):VOr=ucaiFlm.a1wVLFQRmKEhqeC.(s?6=i;f2ZO::?((lh-4Sm[uPnhS#Jkx76Xn5zhYU:$(>czk:+M+F)C]vBUm@Y*5K0EQ]<1]1c", &
        "<7t1.H$75b%>12Y6RQ>e#X?QX8dPnW)5MbnZ2j1#e-DQqUiZejDs2ys>w$H4HT[`*eDcnr#7oSK/dfXV-<SJh_rkIqnkvIK$wmWr#zTCFaT73<vvJVgj_)", &
        "XPbOk0I+9;-j1,>1gj)E3qIVv[0#.=%T:j?E/T.I7gBBJb$jU#8cs=erOoPNX9$j+#zLk#MQtpW<`]W-dC0iRefZS;3RUWCzMi-t;C)tcRUY6,MP@6su2j", &
        "pKlvvt*uQE8zW^<x^e.rxEMxtpMM8jjL6p?VIJ%8u:`->gsa3-Sa3Y.m@$bZ6]1cAqI3<33l-q96mW:7wOC^UhZv46JbjpauieO6BKjilU/Er(y;cvd?1o", &
        "EoRo(m0vh_w:4dfY@>X<CH1#ObC[cU7=8^C-=qVgs=A:Qws=Ha_G6AmRJNq.5?]Bi@Jn@$%Mufi#kSgR-qGOa`K_2VB>FX/b@;skD(A(IHDD^,F.(s8OXm", &
        "1r@V+@H=F@bm0WmHo35+,wWCwq%Nu;E;hq?MUXgOo%%F$L6XeOi=zEQ9stcbhnJZD<6+UG#wzdjI(+]A1yyO.WAw2X_]w<rBcoNn_UY.#P3aP5)Bj4R/ee", &
        "2Q]Oy>OV[p7gK^eAw@6)2Y#sFh@A<CcotB[NH6jur?:+]8aqqc4Qtai(4-OVnpr-c:EB6rgEaD>`(`BFU5IE](bW`.FagB4=Pb.02@V9J87H9I8fFwaZ9B", &
        "sHnzjB78dT_a#KU=9LE5G4*We;QEp=M8.86n*#lJ(9jl[oL$^7DXOgkgMwQ1Q[TvXy],6N[(8Sns<Y%V?3^2ZfoXsP6Bg_V=PN=s[H:E9T47jcI3POqHfd", &
        "@Qfq8Gl1WZn6i;Pr)p,kJ)FV8k@n+(:(uK?tgp4A`NU<qGOMLk%6qnN5bDsY:qQI(X9zcEENNh>gm2UC@vU(#+K+*^PYlVP3VFV#%2@p##+1S,5MG$6x,8", &
        "rh-p<Pfw=DLLHZ.3S.ce@Z9@=n4KJWH`]x(W(@IeP2BoMA@7nr5R1V/6)#fV0(e`LHf0b4i=:Qo@dlY^2u-$:Y<vrI9lFnW^=sZ,p8d;>5ARqAm2XknD_J", &
        "b2dZ/gP3GwP>u?^)5O+]P2bIJnnz3QTsJ@7RwI1qy,vN6#<=Zqa^V#ovZ40CHx9grbA2TvSk2PDZ6,[5QLOTm:ByX-3P>n8I,p36$u0A)+D([Nnx+*1:dp", &
        "53z52B`b;p>MSd[35?V=4SoUYKkI^5f4$qccE])%dSl?]m^72-D[PF?B%eAa`mP9j`ns(/$p]5nKk#PO)u-:OVQU3+>IO<Hr$c0,Xr4H8oD(x(1o>0fAtd", &
        "N6RPP-hBI(G5a3=KXXVcI#FrNfW?j2*O4,[7@VZ2_i`Pp_/mL%ymrth@@?U%P3l@%?iiS<$M5`nh[.na+aL8k6j6(6%=f0gVI*Cn93=B.`^<BVm8,jYGnr", &
        ":pcP3K6^#D>msdWnldMUSsQVDkf,w6.*)Z$oB/1,uj0-R8Ofc=v/^hDv7BB%xCZmV/zE:aK9b>^;;S9VPj#2wd1`ydktv>ZNyt^jQ9^9ty#V$1wb#S8FOW", &
        "7*[a$1QP+y8/iEyi=QrTHiUPi.u-NhG`%P]5+^+nm(52P9^ld%B#K<nr$?*p>]HUTg]o2TORLRd;b%c>HUMPWy-E24_wMM4?kgEk>=GFjvL^k[iB(;Mg$z", &
        "A+s$z5p>bZb@skx=CJ^Z?I0jFI[ymCG=lv$.4kGdwSPEtwMJAwN.gkOLF:iIjJJTheRy>[fxrDdk>:dp[f6<CNNkj5%$SDP]qgjC^E8`*z9?NP;Ad5Hwt*", &
        "gkCai>hsgnc<`,Hf1A:RnwT*UV%LdvIP7#HCsgzu#ObLH>-h[Fo]M(_Iv9,nFMvfi:-FqP?S2#:oajNisyQZ8$j,pg`j-uh>u3-fVXKAD;=Ln>s=HaO=ml", &
        ";^HRqWF,PHK^B]H)9)E>5]4)u`od[5lQqaC`F4gh<5:].BZ/dffcr?x)>=Cm;7?i[%C-=U^;5C5cXdmgMXo9ij4:Ut4C;F#a`jEB=ct*SXm[4GS/<(-gV-", &
        "eaJ7q9Ow>Qeh@S>u?ktjPKv*uA?N3XRjbJeBA=*D;oKFTj,27Os_s9Bo:w^tsOaV]zR`Y#Rb=FTYOa8_pX^J#K1md_?ilm+$.B=5<VDqlNysf[ej[uFTev", &
        "+?gZ6VR0PXbYUi3J[9q)mFIfoifgTgAj7nrp@:C;x5@f0[jEB6o#K;[3gGLMindn]J0-/q)GQI$s3Plj;^,HQ4WHQl3=rrxGD8UqHEbFGA[:iK`opZEXFM", &
        "vYT)ar<9iLnmgVF[0OU-25>ek>b*sENdVJtw@@;6tafC3lXsRbbhiUcE:PJ?2KF(x.bdEu(=5NxM.=m>b.SGwwhN@0as@rtwaj.#N52)o#m:<kK@ou/1F)", &
        "(ttqN?(^YU8FTJfm+t5:.omu7@)_AO@0rXJ8jI(rZ9<?**omYsGbVlOC+KcW#s1#]e#0w;N0kwDP3V>X1888_F/UOZX)7qtipzf6#HUH`DK7[[,T<-ET=M", &
        "DU7`,V3M?u`8`Y?dj)tey=*1k$PP@(6Y/y;$```-3>nxU+P=6I+2$8$^N8qz:93[KrV)pfOBvn1)cvAeotMklS5UzM;GM].f5q;0_tRQ(s>:Zg(_jFZ:#e", &
        "K*sUBJvxtMCP(=2Ed@W8b:yfF<rNq##)EfZ*sqnN0lOU##2Tn%#DHWU6z=0###$8N0o4f#xY?+[/]Kg%#Egr6JNgb`aQi92?(b<Y9Im>LK:FMAE_;U[JLf", &
        "GAgSp-ZNMUXZqSHGju@%QsTa+^(bFv(r+fj)qr@vW@;*I^au?OEm@Z21l@^KkC4<KVfw+a^bICiOZ,Fy)9xnd/[WpbAjxRZSr?S[/_OlTWBUw/jB<IP9;n", &
        "C)1$ts^Q;-BiLSW6Z8<1Pcg(@c((HrO8sjPo$<[IR7?jCAt@]Psw8LW71:8_zMFZ;27[4o4)%r5CvNDA_5>kJ2vOZ@h[eB;^RV4i4sx21i+No6Y89)8oGy", &
        "Ji^i7pKmPt4h1`l?EOBsTYOWZ;Ti:fkfGMuXocT1_X$p9[`)t;dLG15pO31t3Qj:Mf0>GDH)(_OXvL+Cb[(^v>tb[H4Y4s`[KZi38G6?iR#=j3Uk9+B?dZ", &
        "@b[K0X,b[%,6^YR5QNBL(]PSh?=nj@xX8J._x9Z4^D#XQ;%=**uwaFp]jR=8xfql8Ql#vTjk(y/HE-5Di`[HbW$uXg-%<E:yf,7JvQ,He>CcdJVe6DklV(", &
        "@iYjVBT+n1EKJLl:JEA[-44U2.36sdepQ*Zn8_G-#VeMsWWjTvpull<H9s^JE#0h54Q?M>R]LWP1m13Y_)_,gU)[F]gLtG[J>$3(D*OPLNQLSg$4er.nO*", &
        "`jaLPNP;ySR]>(MP+`xRosTNvk/Cjd<HVg>dSwH>L$_AbqEPY=5G%`uNP%r>n,+[80nj=PDr)u((nr_LRMB7R4#L95z%Wv^RUH[.Xgw?GCPrmcjkl:?ap?", &
        "CH4fVd%DHzf6UH3MI<)5>eyRZ+4m-XPxhFSr>Vv,C4pgs]L-7TtTY7]6odsj-kp#_Z*igNMx(Ey[Ga,O/T^E,<)W>$,Vp2Z1js*:[4TFL[TAo(_,5V?RLf", &
        "Hu/(Y<D+*R?`wL_3m.Zunu48*-4>DOEMKNn7#^D:icO;S@7]2X(@IePtiI^Au*WdjSZJ:af12:+az#HdKo`<Q`ur946w;pNDA_v^[.m:p$y?ZpOqN2p=fD", &
        "m:@lkF+WaENuKL@HNZ,WZTUR4p2Ka.odEZLEkL$lZ%5$;ujjz3llTOMaddLG,rDq)YQ--4wZnvfK[,6iQQlK$wS3ioMO,cgWXYRMy#(lPzGw*H*C]m.k^4", &
        "YC5ER<R/6^h:sfXK8;7.nKz<j*1pVYSs-inkbc`35nLS]W.>ig:tg[2<t*6h9Ac_DQoz`p`q),UvUsY90m71##+#*(oK2[e]em#[HIXlRe/q(3zF$OU5<7", &
        "n[0.sZY%[v-Z3DIGgyRpGNw(<Zg/BXqvTSCkl7/@p3Q41HtiV)-7H0^v2v]qY4acM/2;y>+HC2p3)nBaXHH-cX)uWH[37V8EUcI31^c8)Z=_J:ZR.X/a$2", &
        "I6n<sayWXmUTL#9I7Q(N<e=?_ZGxLiveyZ>o44)vS%t#Lx@8[K2A1=9u9NKVNVUQ/_C:DaxP$>HIwVWmpqx@r%iAZUgG@1-MB(RgI*XBKp;8,clgC4%Ylb", &
        "@)=B+gm$=i1PV;V%y#Dv(@IeWTYWvV8$VZ4rtj`P;rBAc5qOa/_ss#gGgMLH(utcB)[bJS2];s0S/fR=f?Flh<xh#i+/skvh?P,>%#:jh#meiwTi:_6lkJ", &
        "RLd6UL@=G/++IX7>h#6,,8U9FalFAye+=/5n0o?pXTe_L$bkA/I*L;d(Ug]J#gLjupf#$8b>2YU-QtMB4DN0wrnY+<T;lQ>Qku1]S0G+d]T*:Z,z;c<2M)", &
        "OeMsc@=ved7n6V(O=.cM4?.tFiD1$[Na5K3lx[<6n<@cXx,-8<O4=T+2N#El`_0N^c6YE%/AOuYUIO3FD9@%=p1x[2XuN5T,Y(9=p/O9,qc`<:y/:@BvDR", &
        "X@+x27k1oX.PTrh=2>L^,@#)ZwXqLw3^Ms(,2ZgJ01Kf<iKigv.]G9Z9]x$[XI%4;v?fDozl3`^X=E(HWuTWm^Qd-4S*_v`PD)dmq?S58<XshfrC@c)a35", &
        "J5sDfn_mc%ObwwXzwvBzQs9Ofc(,6,Z9V=E-1weCEi8C])A<;_1$yZ4l70$p>-R39oDIddwNT;5s83^57?ON;>2FUWXvJAaJ^bkcRKi<T+H]?[BWT8?lV$", &
        "A/Wc0;JyL%El8zlpzs/Hb+@TIU;::cDDMe<Y9>@Fidg$b6F7X+*UfT]R,/6WJ,:.mPv?pZgf+aiIJKAL)*3S]>8Vzxx<[1#x<[1#x<[1#x<[1#x<[1#x<Z", &
        "%l>5yh)%[iO)XNH%xqGb?Qx<[0gx9L=Gx<[1#n`#Oh<1#Ye2aw(z(<-aJGbI_vv?R`gXRmLwo+avkO$GwvYu)U5qQusaRm7G35ZV5I9UCgHQwIS*21d[N#", &
        "722Mk<Xfu#2kE=ub,Qv(nl<0x<[1#x<[1#x<[1#x<[1#x<Oj9x<ZoS^8+1px;hoecX`Oyx9:eVx<[1#x<[1#x<[0z$)Y1/x<[1#x<[1#x<[1#x<[1#x<[1", &
        "#x<[1#x<[0[3LBgJcb8=D#Hnfw#####################2pfdN0kUP#################71O#########)4ST3KXI$z1)V>#t#@jUd9UGlr,l7P7DH", &
        "Iv#%=sMg1Er]4VdWs+#########SYG/@6(JMIb##E5phoi^NrdNLN;3Z#v)+eQLsh>@Y?f$-b<0wZn########################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################################################################################################", &
        "######################################%]E0Hqx$w;5:3J1:@y^Opl6.FMhrKb+Y-eB8,,wqeMO82?cb4;?N$=T2LL1KFsWFtGQXGJ:Z,y;tkFcn", &
        "hwNQ;F95HtTG;*V?cxR-3/v*?N>yoRX3IocYw.)Xiq:WbnH::JejDI[3JEfh)NXU8wygF8fqwb^8MVT_ulfYQ3dxx4/XcO^1qEgR(gu#hB:wGA;=:]6)=#", &
        "JtU^Z0^OT,prOM9fhi,oY4yb[P9BW3ehh7:+*F7w1n55xs<.ko78X/^3gLXfnH?NVQWezB71kA.at,:ZsbcMBkaH(G[l4Q5Mo#OW^Y4SQCh:P]TR(h70/`", &
        "9DHQvVJoLD;eP`##G>r,9txjPsYENAE6Eg%(sdo9oF:(.[7mDDPUg$M7+[ms6hf(i9=Z;EV6Sm5zi)f+PaVtbd+L*YBj1D)1m<9rRFztr+*A(yNA$>0wK3", &
        "@M]tHhrjTtKc_=+.c:55$VrwbcEIUR3Y7V:3j3CK%WP.oXdk/-hLiWZMfVspLr_p?T4tlf.tANmens:<[xPNM2=62Z;U$q-^9`>n<,y.,6@xf=#####:n`", &
        "6j##########%i<u-Fd*aO4sbcw2y^b[<[n%q-mb*U?63>r7LDY.hq.FToM)*K.VVZ(-[al/Xa2oG/0v7$dxrvoIfjg1$=ab:nwyC/CKd8VR4gPl.AyQ_R", &
        "@fIC-DCgO)jH#j.@Jg5%[@7OIObDF^]GdZ)L)=s8[_f18[_h/8[_l%f2uaQf2uaQf2uVWdMc.$Ice_#BI]::5kvT.`#Bt:n=>bk)B+Rdc,[-sg6iD_#QMj", &
        "[.0[jU8FOTFaQC=>oM)*U*8(N=LtdDGYcNp`0A/l6A]x6C`_@)7rzJ+I)4pj47jM<P0I1J_?8z=P/Wbt=/d,[X##-gauUzKW1%Rs*iv%X,J1Zty4+em10O", &
        "nLM8)yuP`kCHP##+aQ2wk6A#r^BysdoLNN>MZ$##nn5+q]1[=OwP]1YMj9#(H;E###%pO,S_jNhKhR###########(]_2#3UJ>N0kUPPbN;`V?J#L01nt@", &
        "_h1X_W#)@0a?%[HdPr.XH=$<$hzFP$(_av)*=cNwGmt8Jej1fp4e8HR4e897BfXy(dk7:0/GI#=25HSd$pKoZeNUd^Ure*Yqb(Q+fe9DC?=)%#7@p0Kfe9", &
        "C8e,_ccFR^g3aYqS01%Ul#ed0)%4I[ZADzU-dSqhGu-.6kwb=y4o(Aaeclvos.T4bQMkSZ0+H7PpRGd]zvUM_xg]ns@8ECJ*cEQVbnCx5cAaBvEhouayq7", &
        "hg9)55uC/@zIZRP/PCX5SVC6:_Tq]4<ufnj#P6zfh^c>eA3>yK_e5a7KR`W2wxcZ-,B,Rb=y-@sCs_8t(K:MV7%RM:VFh,g,GzbB(08==*28Up$;gF^H0^", &
        "7`pJYR8P_yY<o+]@$#vmo,3qRS463)aBJ?e%55G#342+>VbifKYaXmCkTc3.<=YP=A(OILXV2Fq`Y[d_,fe9QuullQQOC1eU.82M+1%Tj@UU3po3njww5J", &
        "BZQ-7Y)>F=N_>w-qc`b]4Ga1>f>2SQVApT?lbCO0LiU.K2v#ezR@pc57+9T?lN=fbo_]T:O2]e/:G=ut`1k$$(Rl########?2O_j+$aN:nT$iY_oe0<33", &
        "nt5t5,oNt8BEhLE;e#Jn)U@G=.b/sg>-g08dxxHTk1ZX#-[al/%.#^7uzw;N$hK[TdPS+HUU4etpco6HFOPnhhvr2w@_.QPpVPMdO8/Mw-,rt;,#CtLS$:", &
        "R/1,ghZ(+x#%fZFv2HJwnyk[XySFd*aOY$5/k6Da]wnE4/P^$$*$FNcZ@W#)@0O#)#mfh^YsIdQR8%Y)O;55FxjemWtCRN$pu*^Ts_PuKW%V?J#QS`4vCA", &
        "H4[+#Ve*#o/QDbIS>.UeO6svf6@Itw:E#07LWNfU/?h)R5)GgV:aQD?cL@mR(zjTUnicS@tw$W54S6Gc:uTNRa.cvWDuatOjSdyHMPfGfbp1vtSV84T:@]", &
        "Ht.EdR=*24;1?:[ZgFb<xUw@Oh]nxu[55^_k7rA$4BfX9lo1ao553`43FNS+]JGCPl8R#N/1C%:M2Cl^b=KKXUUnh6ZaI6/p-,B,ZCEyJ<PK4EkX2_%11Z", &
        "ir8+2)R]))XH>3M$l4bNymyg`kybszXwKg[58q3K]@o))XH1BI%/9JF][laZ-VB=*2AT2Ce%IO(Mt>oj9VdY[_UZECJ*ZG03nSd5IS[7Kvd82wxV^-,Xg:", &
        "AaTELQ,8MR.9RJ=0u(?/p$AJD3p3Kvel-=SR[=)_#######################.j#@$(MYcUlK3YBr*PpupGPpupGPpupGPpupGPpupGPpupGPpupGPpu", &
        "pGPpupGPpupGPpupGPpupGPpupGPpunj#########################################################################(**7uir$=<I)#", &
        "#######*1CS@)Koe6OR$^@c^Pys5AeU4vM:#07>`GKBC.yHbf+::i1*9cAKFa/VUPi%Y@**ydqDNNa=GUk>P<7vpx7.v:Q2.W$yDMc?KCAZvc-`(o4>-2E", &
        ":RbHpd:-fUz)^L,N.G+XH@YhHs.fJnU87gq4@zW1z5B8os;@#D+dA7-S7a+sz`_?w(sI,=N^bHeOfVV<0GUl#d]n[AaIAR%ZLs<2)>psP4,%ix`I3nq)A6", &
        "NSYL%hAZI#pRX)O]zzXztEgsc<H4Ki7)ER0X;1%$I2kg@oUi]nvF8V8I@s]yo*BsYV%]Iza`_=XPoQnOP3q(fKq,4[$bmBJ;gf54S6`?SO)X;vGq1lCR8R", &
        "gE2%j]ns@0ECJ*cCAcyIcuJy4IK))1ouai@7hg9*55uC/?Em-MP1.^%F-2bDRUIz,c/X`hWE9m2=XPtC(yWZKdWl#PgB^DbBJ1]yf`db>t_=YnOubyTUE.", &
        "=#Sqfz$,5jELS$Hs6k1T@F><=.ZApDcD.fAz`0u(=[O1dVHUi`:zBsx949(oTr1%V6</i7Ka#Lc,toqteX]nsX4EBDDCkSZsp,oCnSw9^.>0u(H2;WEgOU", &
        "_JLoA?O?#A=^FwEDYfxT<UI)pi(Y0IymjSVH-ut*EOtt1%V/P.:HIT#vc(.gLk[2_kYd+54S6lA>GeaLARb[C*^*_PK4EkHMU;=TKc(0#:Nqy/f9aFos[c", &
        "NDNT,Q=Y>,GUWXv.DeqW<<#u+Ifi6*5Nk15(RaC0_8QRK)=T9z>0kwUHIq-E7t*2$v2wy=Y57H[[NNky_#.^BN.8il`0u(K)a[euJot#99gK,_Sj#F/6fb", &
        "ojW1Zj1sio:*E+PQKw-.6l=ZH?@K)YcZZ9(]H?1Zj(<$$1nP,24FhD52]P`pUt<T4bQMfGQlFXmt=ugBU0i]nukq547QUMTT3Olsqn1ov/`RJUSo[-,rv("]

    character(len=118), parameter :: BLOB_ROWS_15(24) = [character(len=118) :: &
        "3W;Y?a5_t=lv02Q<o,/]EpW1f#(QDI#,_HC>)ki(vt%Gb<5J$o(Dm0lXdXePK?zw0rOHuwW:B[pZi>tAhNWcM#-QyK?$h.1vt%L8<5MHz(GFm.Z^QEVL<w", &
        "<3rOI2%W:B[pZnI?rhNWec*4PhoCu6@DcD@rESun%gO.H*sd;nKtN#,7goJ`i;/Qyne4^eg_5_]3yv*rWm<65,0#1XN.wq>=lI):ub<zPf)[vii?wcaRgS", &
        "vJZDQf0QJ>VpW0X<S*+npybc#1k,aX@`R)lcLcE+0,.ee?[>c>Uh0koJa:H/RAAR4tvN/FF8`ev*rbZ<6<KV)#Yhg.w1teY*oePKzo^D^9C3@wcaSQSub;", &
        "oO#T5v-PxkVw=fckePP./^h(sC9P34uDOTLVL#4pG`3;^DMVz*2Suc/1Ip,tp(HB_vwv(D%ePP.(DaG:?Qf/qY:C1[VLx#@l37lkN3iQn[_3u*c(PD1sbH", &
        "7WU9$M7bSud.MOQ;7bhmp7aS0L#,sV6l$#v9O(Cm][?vsXJg<PzR](T6@Ae?,aiY#B8ltIBUCW:BEpXy)Jj9N;,fIK(*;AO%S[9N;)wPd[2_ogvs)-y/I`", &
        "v*qy0<5cFw(W5>p=Xa<`vr`+(QeE+9D6XBbM^xp7*qg2iO(5p9Lp1-m%%_AKY<]OLd#ho7Y8^2dYu%cmV$k<B-I-4w89gBLX_j`a3-uk$Lp0tqvFzj46%l", &
        "#E5Hv_;uvcTE$69$mQCCnkCiZmLhjx%ds+SJlfaq7`%mQJRtu(MTue<nhtQF1X@4i#.gTmet)kM,L(UQGJ0uI$.753d,sP9Uo#Vgz>w+:PYf6Od)pyLNR?", &
        "f6C@kBonG(0wT,^ZLaBnr9WyS;C_[/=Y3XCkE-bMya%Bj-x:LS9^5]*p)qTDa#JBM1GTK:4z^(sGGMtdPSk)uaq-V9TW)aO1HHTo]+X4:x51%x#c5;dGhx", &
        "mwq>A7I)OBN=3puehQ<XmwcaYSSvFLz3I9#uOu1Pm,8^3Y0:E2pr#7>A#s1yf`3RXN>Uh-joJ^y^/ZU@fh;NqvA`x:MFHuXj5.HTXf1SN_3[`T?FF8_zv*", &
        "r1J<5n3R*Qm+Snr;Q7)+0>K_lmLO:7z74L%ICLm^^G+wca]TSui+/O*_WP+2w8m3L@B8g?hmi9<Jpp*P7u]11/BnTSF2Kv*r9c<5tGX(dzi;q5qM9c2=qp", &
        "SujZ[O+nDZbAuklx0rh1oJ_uy0Y<zv8<]Z=Bppz6sPra((jSLpuE%nIwcab+SulM:O-9=hcEc^ZhbWa5oJ`G0/Q`sL4JxA9=(*fY3qN@=$M^Ipn.@/1VOs", &
        "W3SH8QUgw[a4uW4^G9lF>n5UWACpRR,4vJ*]2S%0/])3<zl99MSowkEwMYc`Vs$)-w35iDh=j2R7yIlnkRjXxRcM7@?-=hH,#eoB?l]fQA1Ms5PDiO`BYN", &
        "_oNIGbCuI%P[lttV]<v/HhRz#S4HLsQO*dXy>3,HZq7Oc]@G[cM[M)u,44GSUi>S*HDf/cFyt1D9dNR)DhWfFHSrM9.2`uYcfFm$-MezlLPb[mpYcspq^q", &
        "%9msTg6bsm-gRX/QvE=ah/UR(@Y76-[rre@3N^[3iFhkpf>]XL8tWOJG.gm:?-O8)2Wg2O6wC0mx<3iU?%0Z3bG8EgYcw$$]?lN3FmW,S$cTeUrpqfeTYh", &
        "PrC%XR8NIK.b.^v[L`jHMyp6zjiK$:28PvI^iGnr+/S:%ay5iRD/05$fTJ+gXtY$I$g2KNR`uD;<;=UhIqunD^hBFKnD7wjhS7o<v;NdLaH_i)^-%=F7Jy", &
        "Lp0tqvGI*e5F5MuOGX(cOH:NZ8;q[T5:j].lBXfRLp1-o%-fFfY;y:X#4+K]^#AH+<qKLSI<Ph7%GdV9<[BGR?+Kok;hJASLp1-o.%08zM#7%`+*gPDN_1", &
        "WipgxZr9Y5<610S$e)PU.zc0tW(d#ho7Y?9BnBT88SwzdteMyCN_cM@sb2<#vk]y3JWd#k_^%CZS[Cv*+=1U71GI$r@Q@UK6V/uLge,no$vft[E3%g</HI", &
        "t@-,#ev0eWFw]-D)poMUXBNHs53W@_1[V,:8=Av4:GY@iO>>]))X,2JTyUw$+<E4WTZ;kD0b_AU[fqnI+a].(2tEBDQ+[F;@[-[l*zZb*krtFK39[cO]^s", &
        ":.UYx#9wrgWuRVErp^_UC<e08aN3+/6@Luk8nMzO7,.8q0Kjs/WP4+RYWpxLUDIruB<$,L-I1CRhm@9.#Y-r]*LCx%jq7KE4/+z5%LO$mm%VD]]CM8>RDP", &
        "de6<)OoQs>q?P.YoBndFRAzQP<pgsi.>^0D@1gM0`@b%rar,CZqt:DWUT*<,t;wI4gv7C6/dbn`3%tV]WcdvCg811]].PMhBjV(8(0QCiTRxD_GEI<0fwJ", &
        "%h@.lWhF/Uufbo=^-_z.7]b)]A+zZLN;]46,+p;PCsq0Doh4L_<2t+9?2gEoWi%xi-LuRlG8^OP%WyO.BD@W6Ns?^+,G6OvD+Sf,oo$<R<6AM^i@>2VmD>", &
        "C]7fU8fLDyBM*3[HWC]cOtOSy0v,cReED97Djoun,F<9eq-?64i>.^tXOB)5t`QQ>5J,e>B+DuyP`P5[Yk.llalXxBz$%fzf1Kbakil.vk9[_MsIM%F4I3", &
        "ZoaH/NW]fR(=3uPpx5yYL$7q0#)X@%mlU#Kf/88AzmJvq:e>=W@$pC8h4SE2*:V;S@YHgQU(v90[Qwm03Ui026oheKieg_nct+12TI+[c:=hG=tPQc4iUT", &
        ":TXvEPR6bI.0wo6<0A9Gn2=aWXKm34-T(.i(G0Ztzlr=;7C*k9?75Q;O>r?nXB-Jgi3EI:mwi+,u"]

    character(len=118), parameter :: BLOB_ROWS(1424) = [ &
        BLOB_ROWS_1, &
        BLOB_ROWS_2, &
        BLOB_ROWS_3, &
        BLOB_ROWS_4, &
        BLOB_ROWS_5, &
        BLOB_ROWS_6, &
        BLOB_ROWS_7, &
        BLOB_ROWS_8, &
        BLOB_ROWS_9, &
        BLOB_ROWS_10, &
        BLOB_ROWS_11, &
        BLOB_ROWS_12, &
        BLOB_ROWS_13, &
        BLOB_ROWS_14, &
        BLOB_ROWS_15]

end module fplotlib_glyphs_data
