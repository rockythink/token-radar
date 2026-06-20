import Foundation

public enum OpenAIUsageExtractor {
    public struct ExtractedUsage: Equatable {
        public var model: String
        public var inputTokens: Int
        public var outputTokens: Int

        public init(model: String, inputTokens: Int, outputTokens: Int) {
            self.model = model
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }
    }

    public static func extract(
        responseData: Data,
        requestData: Data,
        fallbackModel: String = "unknown"
    ) -> ExtractedUsage? {
        let responseObject = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
        let requestObject = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any]
        let usage = responseObject?["usage"] as? [String: Any]

        let responseModel = responseObject?["model"] as? String
        let requestModel = requestObject?["model"] as? String
        let model = responseModel ?? requestModel ?? fallbackModel

        let inputTokens = DecimalCoding.int(
            from: usage?["input_tokens"] ??
            usage?["prompt_tokens"] ??
            usage?["inputTokens"] ??
            usage?["promptTokens"]
        )

        let outputTokens = DecimalCoding.int(
            from: usage?["output_tokens"] ??
            usage?["completion_tokens"] ??
            usage?["outputTokens"] ??
            usage?["completionTokens"]
        )

        guard inputTokens > 0 || outputTokens > 0 else {
            return nil
        }

        return ExtractedUsage(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
    }
}

