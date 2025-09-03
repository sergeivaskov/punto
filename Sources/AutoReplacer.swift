import Foundation

/// Состояния автозамены
public enum ReplacementState: Equatable {
    case idle
    case analyzing
    case ambiguous(waitingFor: String)
    case replacing
}

/// Результат анализа токена
public enum ReplacementDecision {
    case noAction
    case replace(from: String, to: String, targetLayout: KeyboardLayout)
    case waitForMore
}

/// Pre-calculated execution plan for efficient replacement
struct ExecutionPlan {
    let originalToken: String
    let deleteCount: Int
    let replacementText: String
    let targetLayout: KeyboardLayout
}

/// Движок автозамены с логикой принятия решений
public final class AutoReplacer {
    private var state: ReplacementState = .idle
    private let converter = QwertyJcukenLayoutConverter()
    private weak var executor: ReplacementExecutor?
    private var plannedExecution: ExecutionPlan? = nil
    
    public init() {}
    
    public func setExecutor(_ executor: ReplacementExecutor) {
        self.executor = executor
    }
    
    public func analyzeToken(_ token: String) {
        guard token.count >= 3, state != .replacing else { return }
        state = .analyzing
        executeDecision(makeDecision(token: token, analysis: DictionaryManager.shared.analyzePrefix(token)))
    }
    
    private func makeDecision(token: String, analysis: PrefixAnalysis) -> ReplacementDecision {
        switch analysis {
        case .tooShort: 
            return .noAction
        case .onlyEnglish, .onlyRussian:
            // Enhanced логика: проверить конвертированную версию как complete word
            let convertedToken = converter.convertToOppositeLayout(token)
            let convertedAnalysis = DictionaryManager.shared.analyzeCompleteWord(convertedToken)
            
            if convertedAnalysis == .onlyEnglish || convertedAnalysis == .onlyRussian {
                Log.d("AutoReplacer", "'\(token)': prefix in current, complete word in opposite → converting")
                return analyzeConverted(token, logContext: "prefix→complete")
            } else {
                Log.d("AutoReplacer", "'\(token)': correct layout")
                return .noAction
            }
        case .ambiguous:
            Log.d("AutoReplacer", "'\(token)': ambiguous - waiting")
            state = .ambiguous(waitingFor: token)
            return .waitForMore
        case .none:
            return analyzeConvertedToken(token)
        }
    }
    
    private func analyzeConvertedToken(_ originalToken: String) -> ReplacementDecision {
        let convertedToken = converter.convertToOppositeLayout(originalToken)
        switch DictionaryManager.shared.analyzePrefix(convertedToken) {
        case .onlyEnglish:
            Log.d("AutoReplacer", "'\(originalToken)' → '\(convertedToken)': EN")
            return .replace(from: originalToken, to: convertedToken, targetLayout: .enUS)
        case .onlyRussian:
            Log.d("AutoReplacer", "'\(originalToken)' → '\(convertedToken)': RU")
            return .replace(from: originalToken, to: convertedToken, targetLayout: .ruRU)
        case .ambiguous:
            Log.d("AutoReplacer", "'\(originalToken)' → '\(convertedToken)': ambiguous")
            state = .ambiguous(waitingFor: originalToken)
            return .waitForMore
        default:
            Log.d("AutoReplacer", "'\(originalToken)' → '\(convertedToken)': no match")
            return .noAction
        }
    }
    
    private func executeDecision(_ decision: ReplacementDecision) {
        switch decision {
        case .noAction:
            state = .idle
        case .replace(let from, let to, let targetLayout):
            state = .replacing
            executor?.executeReplacement(originalLength: from.count, replacementText: to, targetLayout: targetLayout) { [weak self] success in
                self?.state = .idle
                Log.d("AutoReplacer", "Replacement \(success ? "completed" : "failed"): '\(from)' → '\(to)'")
            }
        case .waitForMore:
            break // State set in makeDecision
        }
    }
    
    public func reset() {
        if case .ambiguous = state { Log.d("AutoReplacer", "Reset ambiguous") }
        state = .idle
    }
    
    public func cancel() {
        Log.d("AutoReplacer", "Cancel")
        state = .idle
        plannedExecution = nil
    }
    
    public func analyzeTokenForPlanning(_ token: String) {
        guard token.count >= 3, state != .replacing else { 
            plannedExecution = nil
            return 
        }
        
        let decision = makeDecision(token: token, analysis: DictionaryManager.shared.analyzePrefix(token))
        if case .replace(let from, let to, let targetLayout) = decision {
            Log.d("AutoReplacer", "Planned: '\(token)' → delete \(from.count), type '\(to)'")
            plannedExecution = createExecutionPlan(from: from, to: to, targetLayout: targetLayout)
        } else {
            Log.d("AutoReplacer", "No plan: '\(token)'")
            plannedExecution = nil
        }
    }
    
    public func executePlannedReplacement(completion: @escaping (Bool, String, String) -> Void = { _, _, _ in }) {
        guard let plan = plannedExecution else { 
            completion(false, "", "")
            return 
        }
        
        Log.d("AutoReplacer", "Executing: delete \(plan.deleteCount), type '\(plan.replacementText)'")
        state = .replacing
        executor?.executeReplacement(
            originalLength: plan.deleteCount,
            replacementText: plan.replacementText,
            targetLayout: plan.targetLayout
        ) { [weak self] success in
            self?.state = .idle
            self?.plannedExecution = nil
            Log.d("AutoReplacer", "Execution \(success ? "completed" : "failed"): '\(plan.replacementText)'")
            completion(success, plan.originalToken, plan.replacementText)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createExecutionPlan(from: String, to: String, targetLayout: KeyboardLayout, includeSpace: Bool = false) -> ExecutionPlan {
        ExecutionPlan(
            originalToken: from,
            deleteCount: from.count + (includeSpace ? 1 : 0),
            replacementText: to + (includeSpace ? " " : ""),
            targetLayout: targetLayout
        )
    }
    
    private func analyzeConverted(_ originalToken: String, logContext: String = "") -> ReplacementDecision {
        let convertedToken = converter.convertToOppositeLayout(originalToken)
        switch DictionaryManager.shared.analyzeCompleteWord(convertedToken) {
        case .onlyEnglish:
            Log.d("AutoReplacer", "\(logContext) '\(originalToken)' → '\(convertedToken)': EN word")
            return .replace(from: originalToken, to: convertedToken, targetLayout: .enUS)
        case .onlyRussian:
            Log.d("AutoReplacer", "\(logContext) '\(originalToken)' → '\(convertedToken)': RU word")
            return .replace(from: originalToken, to: convertedToken, targetLayout: .ruRU)
        case .ambiguous:
            Log.d("AutoReplacer", "\(logContext) '\(originalToken)' → '\(convertedToken)': ambiguous")
            return .noAction
        default:
            Log.d("AutoReplacer", "\(logContext) '\(originalToken)' → '\(convertedToken)': no match")
            return .noAction
        }
    }
    
    // MARK: - Short Token Analysis
    
    public func analyzeShortTokenWithSpace(_ token: String) {
        guard token.count < 3 && !token.isEmpty, state != .replacing else { 
            plannedExecution = nil
            return 
        }
        
        Log.d("AutoReplacer", "🔤 SHORT TOKEN: analyzing '\(token)' as complete word")
        let decision = makeShortTokenDecision(token: token, analysis: DictionaryManager.shared.analyzeCompleteWord(token))
        
        if case .replace(let from, let to, let targetLayout) = decision {
            // Включаем пробел в замену: delete token+space, type converted+space
            Log.d("AutoReplacer", "🔤 PLANNED SHORT: '\(token)' → delete \(from.count + 1), type '\(to) '")
            plannedExecution = createExecutionPlan(from: from, to: to, targetLayout: targetLayout, includeSpace: true)
        } else {
            Log.d("AutoReplacer", "🔤 NO SHORT PLAN: '\(token)'")
            plannedExecution = nil
        }
    }
    
    private func makeShortTokenDecision(token: String, analysis: PrefixAnalysis) -> ReplacementDecision {
        guard analysis != .tooShort && analysis != .ambiguous else { return .noAction }
        
        let convertedToken = converter.convertToOppositeLayout(token)
        let convertedAnalysis = DictionaryManager.shared.analyzeCompleteWord(convertedToken)
        
        switch (analysis, convertedAnalysis) {
        case (.onlyEnglish, .onlyRussian), (.onlyRussian, .onlyEnglish):
            Log.d("AutoReplacer", "🔤 '\(token)' ↔ '\(convertedToken)': both complete → ambiguous")
            return .noAction
        case (.none, .onlyEnglish), (.none, .onlyRussian):
            Log.d("AutoReplacer", "🔤 '\(token)' → '\(convertedToken)': converting to complete word")
            return analyzeConverted(token, logContext: "🔤")
        case (.onlyEnglish, _), (.onlyRussian, _):
            Log.d("AutoReplacer", "🔤 '\(token)': correct layout")
            return .noAction
        default:
            Log.d("AutoReplacer", "🔤 '\(token)': no valid conversion")
            return .noAction
        }
    }
    

}
