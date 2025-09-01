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
            Log.d("AutoReplacer", "'\(token)': correct layout")
            return .noAction
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
            plannedExecution = ExecutionPlan(originalToken: from, deleteCount: from.count, replacementText: to, targetLayout: targetLayout)
        } else {
            Log.d("AutoReplacer", "No plan: '\(token)'")
            plannedExecution = nil
        }
    }
    
    public func executePlannedReplacement(completion: @escaping (Bool) -> Void = { _ in }) {
        executePlannedReplacement { success, _, _ in completion(success) }
    }
    
    public func executePlannedReplacement(completion: @escaping (Bool, String, String) -> Void) {
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
}
