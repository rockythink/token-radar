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
        let responsePayload = responseObject?["response"] as? [String: Any]
        let usage = responseObject?["usage"] as? [String: Any] ?? responsePayload?["usage"] as? [String: Any]

        let responseModel = responseObject?["model"] as? String ?? responsePayload?["model"] as? String
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

    public static func extractEventStream(
        responseData: Data,
        requestData: Data,
        fallbackModel: String = "unknown"
    ) -> ExtractedUsage? {
        guard let text = String(data: responseData, encoding: .utf8) else {
            return nil
        }

        var latestUsage: ExtractedUsage?
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }

            let payload = trimmed
                .dropFirst("data:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard payload != "[DONE]", let data = payload.data(using: .utf8) else {
                continue
            }

            if let extracted = extract(responseData: data, requestData: requestData, fallbackModel: fallbackModel) {
                latestUsage = extracted
            }
        }

        return latestUsage
    }
}
