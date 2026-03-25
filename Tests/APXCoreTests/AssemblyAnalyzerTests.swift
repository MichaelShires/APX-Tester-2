import XCTest
@testable import APXCore

final class AssemblyAnalyzerTests: XCTestCase {

    let analyzer = AssemblyAnalyzer()

    func testFindsAPXInstructions() {
        let assembly = """
            .text
            .globl  _test
        _test:
            pushq   %rbp
            ccmp    %rdi, %rsi, 0, e
            cfcmov  %rax, %rbx, ne
            popq    %rbp
            retq
        """

        let matches = analyzer.findAPXInstructions(in: assembly)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].instruction, .ccmp)
        XCTAssertEqual(matches[1].instruction, .cfcmov)
    }

    func testNoMatchesInRegularAssembly() {
        let assembly = """
            pushq   %rbp
            movq    %rsp, %rbp
            cmpq    %rdi, %rsi
            cmovl   %rdi, %rax
            popq    %rbp
            retq
        """

        let matches = analyzer.findAPXInstructions(in: assembly)
        XCTAssertTrue(matches.isEmpty)
    }
}
