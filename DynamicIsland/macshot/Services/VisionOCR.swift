import Vision

enum VisionOCR {

    static func makeTextRecognitionRequest(
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) -> VNRecognizeTextRequest {
        makeTextRecognitionRequest(recognitionLevel: .accurate, completionHandler: completionHandler)
    }

    static func performTextRecognition(
        cgImage: CGImage,
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) {
        // Preserve accurate OCR when it works; fall back for platform model failures.
        performTextRecognition(
            cgImage: cgImage,
            recognitionLevel: .accurate,
            retryWithFastOnFailure: true,
            completionHandler: completionHandler)
    }

    private static func performTextRecognition(
        cgImage: CGImage,
        recognitionLevel: VNRequestTextRecognitionLevel,
        retryWithFastOnFailure: Bool,
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) {
        let request = makeTextRecognitionRequest(recognitionLevel: recognitionLevel) { request, error in
            if retryWithFastOnFailure, error != nil {
                performTextRecognition(
                    cgImage: cgImage,
                    recognitionLevel: .fast,
                    retryWithFastOnFailure: false,
                    completionHandler: completionHandler)
                return
            }
            completionHandler(request, error)
        }

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            if retryWithFastOnFailure {
                performTextRecognition(
                    cgImage: cgImage,
                    recognitionLevel: .fast,
                    retryWithFastOnFailure: false,
                    completionHandler: completionHandler)
            } else {
                completionHandler(request, error)
            }
        }
    }

    private static func makeTextRecognitionRequest(
        recognitionLevel: VNRequestTextRecognitionLevel,
        completionHandler: @escaping (VNRequest, Error?) -> Void
    ) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest(completionHandler: completionHandler)
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        return request
    }

}
