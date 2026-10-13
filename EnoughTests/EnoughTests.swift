//
//  EnoughTests.swift
//  EnoughTests
//
//  Created by Rodrigo Cortez on 07/10/26.
//

import Testing
@testable import Enough

struct EnoughTests {
    @Test func classifiesVerifiedC2PADigitalSourceTypes() {
        #expect(
            ImageC2PA.classify(
                manifestJSON: """
                {"assertions":[{"data":{"digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"}}]}
                """
            ) == .verifiedAI
        )
        #expect(
            ImageC2PA.classify(
                manifestJSON: """
                {"assertions":[{"data":{"digitalSourceType":"http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"}}]}
                """
            ) == .verifiedReal
        )
        #expect(
            ImageC2PA.classify(manifestJSON: #"{"assertions":[]}"#) == .unknown
        )
    }
}
