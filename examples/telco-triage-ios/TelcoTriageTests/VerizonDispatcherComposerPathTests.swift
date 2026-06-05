import XCTest
@testable import TelcoTriage

/// End-to-end smoke tests for the Step 6.4 composer path through
/// `VerizonChatDispatcher`. Exercises the route-derivation gate
/// (`ToolRegistry`) + lexical retrieval + composer wiring.
///
/// These tests use a stub Stage A classifier so they don't need
/// llama_cpp models or the full app stack — the composer path only
/// requires `composer + corpus + lexicalRetriever + toolRegistry`.
@MainActor
final class VerizonDispatcherComposerPathTests: XCTestCase {
    private var corpus: RAGUnitCorpus!
    private var retriever: BM25HierarchyRetriever!
    private var composer: DeterministicAnswerComposer!
    private var toolRegistry: ToolRegistry!

    override func setUpWithError() throws {
        try super.setUpWithError()
        corpus = try RAGUnitCorpus.loadFromBundle()
        retriever = BM25HierarchyRetriever(corpus: corpus)
        composer = DeterministicAnswerComposer()
        toolRegistry = ToolRegistry.default(customerContext: CustomerContext())
    }

    // MARK: - tool_action: real tool exists

    func test_restart_router_routes_to_toolAction_with_confirmation() async {
        let result = await dispatch(query: "restart my router")
        XCTAssertEqual(result.source, .composer)
        XCTAssertEqual(result.composerRoute, .toolAction)
        XCTAssertEqual(result.requiresConfirmation, true,
                       "restart-router is a registered ToolIntent with requiresConfirmation=true")
        XCTAssertEqual(result.citedRAGUnit?.pageID, "02.07")
        XCTAssertTrue(result.text.lowercased().contains("confirm"),
                      "tool_action text must carry the Confirm clause")
    }

    func test_speed_test_action_fires_without_confirmation() async {
        // run-speed-test is registered but ToolIntent.requiresConfirmation = false
        // (read-only — no destructive side effect)
        let result = await dispatch(query: "run a speed test")
        XCTAssertEqual(result.composerRoute, .toolAction)
        XCTAssertEqual(result.requiresConfirmation, false)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "01.02")
    }

    // MARK: - answer_plus_action: question form + real tool

    func test_question_about_restart_routes_to_answerPlusAction() async {
        let result = await dispatch(query: "how do I restart my router?")
        XCTAssertEqual(result.composerRoute, .answerPlusAction,
                       "Question form of a real-tool action → explain + offer")
        XCTAssertEqual(result.requiresConfirmation, true)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "02.07")
    }

    // MARK: - rag_answer: NO tool exists (no theatre confirmation)

    func test_change_wifi_password_is_rag_answer_no_confirmation() async {
        // 03.00 Network — no ToolIntent registered for `network` linkID.
        // Per guardrail #3, no confirmation theatre.
        let result = await dispatch(query: "change my wifi password")
        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.requiresConfirmation, false,
                       "no real tool → no confirmation theatre (guardrail #3)")
        XCTAssertEqual(result.citedRAGUnit?.pageID, "03.00")
        XCTAssertFalse(result.text.lowercased().contains("reply 'yes'"),
                       "view-only page must NOT show the yes-to-confirm clause")
    }

    func test_share_wifi_password_is_rag_answer_no_confirmation() async {
        // 03.02 Share Wi-Fi — no ToolIntent registered for `share-wifi`.
        let result = await dispatch(query: "share my wifi password")
        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.requiresConfirmation, false)
    }

    func test_create_profile_is_grounded_navigation_not_fake_tool() async {
        // 13.02 has action-like language, but no registered create-profile
        // tool exists. The composer should explain/open the page, not
        // manufacture a confirmation flow via the shared `home` link_id.
        let result = await dispatch(query: "add a profile for my son")
        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.requiresConfirmation, false)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "13.02")
        XCTAssertTrue(result.text.contains("group their children's devices"))
        XCTAssertFalse(result.text.contains("I found the relevant page"))
        XCTAssertFalse(result.text.contains("Reply 'yes'"))
    }

    // MARK: - Multi-turn reuse

    func test_how_to_do_it_reuses_prior_parental_controls_page() async {
        let context = RetrievalContext(
            priorAssistantText: nil,
            priorPageID: "13.00",
            priorLinkID: "home"
        )
        let result = await dispatch(query: "Can you tell me how to do it", context: context)

        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "13.00")
        XCTAssertFalse(
            result.text.lowercased().contains("don't have specific information"),
            "anaphoric follow-up should reuse prior Parental Controls evidence, not fall back to no_rag_answer"
        )
    }

    func test_cannot_find_restart_button_uses_active_restart_task() async {
        let context = RetrievalContext(
            priorAssistantText: nil,
            priorPageID: "02.07",
            priorLinkID: "restart-router"
        )
        let result = await dispatch(query: "Not able to find restart button", context: context)

        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "02.07")
        XCTAssertEqual(result.citedRAGUnit?.linkID, "restart-router")
        XCTAssertFalse(
            result.text.lowercased().contains("set-top box"),
            "active restart-router task should not drift to set-top-box restart content"
        )
    }

    func testEquipmentTileFollowupAnswersRestartSubstep() async {
        let context = RetrievalContext(
            priorAssistantText: nil,
            priorPageID: "02.07",
            priorLinkID: "restart-router"
        )
        let result = await dispatch(query: "Where is the equipment tile", context: context)

        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "02.07")
        XCTAssertTrue(result.text.contains("Equipment"))
        XCTAssertTrue(result.text.contains("Home page"))
        XCTAssertFalse(
            result.text.lowercased().contains("equipment details"),
            "sub-step follow-up should not be re-synthesized as the Equipment details page"
        )
        XCTAssertFalse(
            result.text.lowercased().contains("want me to do this"),
            "a navigation sub-question inside a tool flow should not create a fresh confirmation offer"
        )
    }

    func test_active_task_context_does_not_block_clear_new_topic() async {
        let context = RetrievalContext(
            priorAssistantText: nil,
            priorPageID: "02.07",
            priorLinkID: "restart-router"
        )
        let result = await dispatch(query: "show me my connected devices", context: context)

        XCTAssertEqual(result.composerRoute, .ragAnswer)
        XCTAssertEqual(result.citedRAGUnit?.pageID, "04.00")
        XCTAssertEqual(result.citedRAGUnit?.linkID, "tab-devices")
    }

    // MARK: - Link grounding: composer only renders selected unit's URL

    func test_rendered_link_is_canonical_url_of_selected_unit() async {
        let result = await dispatch(query: "restart my router")
        let expected = corpus.unit(forPageID: "02.07")?.canonicalURL
        XCTAssertEqual(result.deepLink, expected,
                       "composer can only render the selected unit's canonical_url")
    }

    func test_rendered_link_present_in_known_canonical_set() async {
        let known = corpus.allCanonicalURLs
        for query in [
            "restart my router", "change wifi password", "show me my devices",
            "run a speed test", "share my wifi", "parental controls",
        ] {
            let result = await dispatch(query: query)
            guard let link = result.deepLink else { continue }
            XCTAssertTrue(
                known.contains(link) || known.contains(link.split(separator: "?").first.map(String.init) ?? link),
                "composer rendered an unknown vzhome:// URL on query '\(query)': \(link)"
            )
        }
    }

    // MARK: - Runtime split

    func test_dispatchComposer_doesNotInvokeStageAOrLegacyEvents() async {
        let stageA = CountingStageAClassifier()
        let dispatcher = makeDispatcher(stageA: stageA)

        var events: [VerizonDispatchEvent] = []
        for await event in dispatcher.dispatchComposer(query: "restart my router") {
            events.append(event)
        }

        let stageACalls = await stageA.callCount()
        XCTAssertEqual(stageACalls, 0)
        XCTAssertFalse(events.contains(.stageAStarted))
        XCTAssertFalse(events.contains(.stageBStarted))
        XCTAssertFalse(events.contains { event in
            if case .stageAComplete = event { return true }
            return false
        })
    }

    func test_chatViewModelComposerPathBypassesCompositeUnderstandingAndRelationalStack() async {
        let stageA = CountingStageAClassifier()
        let understanding = CountingUnderstandingClassifier()
        let relational = CountingRelationalStrategy()
        let dispatcher = makeDispatcher(stageA: stageA)
        let harness = TestChatHarness(
            verizonDispatcher: dispatcher,
            understandingClassifier: understanding,
            relationalStrategy: relational
        )

        await harness.send("restart my router")

        let stageACalls = await stageA.callCount()
        let understandingCalls = await understanding.callCount()
        let relationalTextCalls = await relational.textCallCount()
        let chatModeCalls = await harness.chatModeRouter.recordedQueryCount()
        XCTAssertEqual(stageACalls, 0)
        XCTAssertEqual(understandingCalls, 0)
        XCTAssertEqual(relationalTextCalls, 0)
        XCTAssertEqual(chatModeCalls, 0)
        XCTAssertEqual(harness.lastAssistantMessage?.trace?.chatModeRuntimeMS, 0)
        XCTAssertNotNil(harness.lastAssistantMessage?.trace?.retrievalMS)
        XCTAssertNotNil(harness.lastAssistantMessage?.trace?.routePolicyMS)
        XCTAssertNotNil(harness.lastAssistantMessage?.trace?.composerMS)
        XCTAssertNotNil(harness.lastAssistantMessage?.trace?.totalWallMS)
    }

    // MARK: - Helpers

    private func makeDispatcher(stageA: VerizonStageAClassifying? = nil) -> VerizonChatDispatcher {
        VerizonChatDispatcher(
            stageA: stageA,
            stageB: nil,
            kbFallback: StubKBExtractor(),
            kb: [],
            retriever: nil,
            modelHost: nil,
            composer: composer,
            corpus: corpus,
            lexicalRetriever: retriever,
            toolRegistry: toolRegistry,
            toolAliasMap: ToolAliasMap.default()
        )
    }

    private func dispatch(
        query: String,
        context: RetrievalContext = .empty
    ) async -> VerizonDispatchResult {
        let dispatcher = makeDispatcher()
        var finalResult: VerizonDispatchResult?
        for await event in dispatcher.dispatchComposer(
            query: query,
            retrievalContext: context
        ) {
            if case .response(let r) = event { finalResult = r }
        }
        return finalResult ?? VerizonDispatchResult(
            text: "<no response>", lane: .ragStepByStep, source: .composer, totalMs: 0
        )
    }
}

// MARK: - Stage A stub

private func makeStageADecision() -> VerizonStageADecision {
    VerizonStageADecision(
        topicGate: .inScope,
        topicGateConfidence: 0.95,
        topicGateProbabilities: [0.05, 0.95],
        refusalFlags: .none,
        refusalFlagsProbabilities: [0, 0, 0],
        totalMs: 0
    )
}

private struct StubStageAClassifier: VerizonStageAClassifying {
    func classify(query: String) async throws -> VerizonStageADecision {
        makeStageADecision()
    }
}

private actor CountingStageAClassifier: VerizonStageAClassifying {
    private var calls = 0

    func classify(query: String) async throws -> VerizonStageADecision {
        calls += 1
        return makeStageADecision()
    }

    func callCount() -> Int {
        calls
    }
}

private actor CountingUnderstandingClassifier: QueryUnderstandingClassifying {
    private var calls = 0

    func classify(query: String) async throws -> QueryUnderstanding {
        calls += 1
        return QueryUnderstanding(
            chatMode: ChatModePrediction(
                mode: .kbQuestion,
                confidence: 1.0,
                reasoning: "test should not be called",
                runtimeMS: 1
            )
        )
    }

    func callCount() -> Int {
        calls
    }
}

private actor CountingRelationalStrategy: RelationalHeadsStrategy {
    private var classifyCalls = 0
    private var textCalls = 0

    func classify(
        currentUserQuery: String,
        priorUserHidden: [Float]?,
        priorAssistantHidden: [Float]?
    ) async throws -> RelationalOutcomes {
        classifyCalls += 1
        return .none
    }

    func classifyFromText(
        currentUserQuery: String,
        priorAssistantText: String?,
        priorUserText: String?
    ) async throws -> RelationalOutcomes {
        textCalls += 1
        return .none
    }

    func textCallCount() -> Int {
        textCalls
    }
}

private extension ScriptedChatModeRouter {
    func recordedQueryCount() -> Int {
        recordedQueries.count
    }
}
