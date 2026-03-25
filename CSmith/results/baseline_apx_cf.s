	.build_version macos, 26, 0	sdk_version 26, 2
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_apx_ccmp_and                   ## -- Begin function apx_ccmp_and
	.p2align	4
_apx_ccmp_and:                          ## @apx_ccmp_and
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%edx, %edi
	ccmpgl	{dfv=}	%ecx, %esi
	setzul	%al
	movzbl	%al, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ccmp_or                    ## -- Begin function apx_ccmp_or
	.p2align	4
_apx_ccmp_or:                           ## @apx_ccmp_or
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%edx, %edi
	ccmplel	{dfv=sf}	%ecx, %esi
	setzul	%al
	movzbl	%al, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ccmp_range                 ## -- Begin function apx_ccmp_range
	.p2align	4
_apx_ccmp_range:                        ## @apx_ccmp_range
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%esi, %edi
	ccmpgel	{dfv=}	%edx, %edi
	setzule	%al
	movzbl	%al, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ndd_ternary                ## -- Begin function apx_ndd_ternary
	.p2align	4
_apx_ndd_ternary:                       ## @apx_ndd_ternary
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	testl	%edx, %edx
	cmovgl	%edi, %esi, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ndd_min                    ## -- Begin function apx_ndd_min
	.p2align	4
_apx_ndd_min:                           ## @apx_ndd_min
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%esi, %edi
	cmovll	%edi, %esi, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ndd_clamp                  ## -- Begin function apx_ndd_clamp
	.p2align	4
_apx_ndd_clamp:                         ## @apx_ndd_clamp
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%esi, %edi
	cmovgl	%edi, %esi, %eax
	cmpl	%edx, %eax
	cmovgel	%edx, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_cfcmov_load                ## -- Begin function apx_cfcmov_load
	.p2align	4
_apx_cfcmov_load:                       ## @apx_cfcmov_load
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	testl	%edi, %edi
	cfcmovnel	(%rsi), %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_cfcmov_store               ## -- Begin function apx_cfcmov_store
	.p2align	4
_apx_cfcmov_store:                      ## @apx_cfcmov_store
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	testl	%edi, %edi
	cfcmovnel	%edx, (%rsi)
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ccmp_and_inline            ## -- Begin function apx_ccmp_and_inline
	.p2align	4
_apx_ccmp_and_inline:                   ## @apx_ccmp_and_inline
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%edx, %edi
	ccmpgl	{dfv=}	%ecx, %esi
	setzul	%al
	movzbl	%al, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ndd_ternary_inline         ## -- Begin function apx_ndd_ternary_inline
	.p2align	4
_apx_ndd_ternary_inline:                ## @apx_ndd_ternary_inline
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	testl	%edx, %edx
	cmovgl	%edi, %esi, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_apx_ccmp_range_inline          ## -- Begin function apx_ccmp_range_inline
	.p2align	4
_apx_ccmp_range_inline:                 ## @apx_ccmp_range_inline
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	cmpl	%esi, %edi
	ccmpgel	{dfv=}	%edx, %edi
	setzule	%al
	movzbl	%al, %eax
	popp	%rbp
	retq
	.cfi_endproc
                                        ## -- End function
	.globl	_main                           ## -- Begin function main
	.p2align	4
_main:                                  ## @main
	.cfi_startproc
## %bb.0:
	pushp	%rbp
	.cfi_def_cfa_offset 16
	.cfi_offset %rbp, -16
	movq	%rsp, %rbp
	.cfi_def_cfa_register %rbp
	push2p	%r14, %r15
	push2p	%r12, %r13
	pushp	%rbx
	subq	$40, %rsp
	.cfi_offset %rbx, -56
	.cfi_offset %r12, -48
	.cfi_offset %r13, -40
	.cfi_offset %r14, -32
	.cfi_offset %r15, -24
	movq	___stack_chk_guard@GOTPCREL(%rip), %rax
	movq	(%rax), %rax
	movq	%rax, -48(%rbp)
	movl	$1, -80(%rbp)
	movl	$2, -76(%rbp)
	movl	$3, -72(%rbp)
	movl	$4, -68(%rbp)
	movl	-80(%rbp), %ebx
	movl	-76(%rbp), %r14d
	movl	-72(%rbp), %r15d
	movl	-68(%rbp), %r12d
	movl	%ebx, -64(%rbp)
	leaq	-60(%rbp), %r13
	movl	%r14d, -60(%rbp)
	movl	%r15d, -56(%rbp)
	movl	%r12d, -52(%rbp)
	movl	%ebx, %edi
	movl	%r14d, %esi
	movl	%r15d, %edx
	movl	%r12d, %ecx
	callq	_apx_ccmp_and
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movl	%r14d, %esi
	movl	%r15d, %edx
	movl	%r12d, %ecx
	callq	_apx_ccmp_or
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movl	%r14d, %esi
	movl	%r15d, %edx
	callq	_apx_ccmp_range
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movl	%r14d, %esi
	movl	%r15d, %edx
	callq	_apx_ndd_ternary
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movl	%r14d, %esi
	callq	_apx_ndd_min
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movl	%r14d, %esi
	movl	%r15d, %edx
	callq	_apx_ndd_clamp
	addl	%eax, _apx_sink(%rip)
	leaq	-64(%rbp), %rsi
	movl	%ebx, %edi
	callq	_apx_cfcmov_load
	addl	%eax, _apx_sink(%rip)
	movl	%ebx, %edi
	movq	%r13, %rsi
	movl	%r14d, %edx
	callq	_apx_cfcmov_store
	movl	-60(%rbp), %eax
	addl	%eax, _apx_sink(%rip)
	cmpl	%r15d, %ebx
	ccmpgl	{dfv=}	%r12d, %r14d
	setzul	%al
	movzbl	%al, %eax
	addl	%eax, _apx_sink(%rip)
	testl	%r15d, %r15d
	cmovgl	%ebx, %r14d, %eax
	addl	%eax, _apx_sink(%rip)
	cmpl	%r14d, %ebx
	ccmpgel	{dfv=}	%r15d, %ebx
	setzule	%al
	movzbl	%al, %eax
	addl	%eax, _apx_sink(%rip)
	movl	_apx_sink(%rip), %eax
	movq	___stack_chk_guard@GOTPCREL(%rip), %rcx
	movq	(%rcx), %rcx
	cmpq	-48(%rbp), %rcx
	jne	LBB11_2
## %bb.1:
	addq	$40, %rsp
	popp	%rbx
	pop2p	%r13, %r12
	pop2p	%r15, %r14
	popp	%rbp
	retq
LBB11_2:
	callq	___stack_chk_fail
	.cfi_endproc
                                        ## -- End function
.zerofill __DATA,__bss,_apx_sink,4,2    ## @apx_sink
.subsections_via_symbols
