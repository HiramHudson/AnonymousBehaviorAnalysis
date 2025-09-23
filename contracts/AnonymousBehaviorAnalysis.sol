// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE, euint8, euint16, euint32, ebool } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract AnonymousBehaviorAnalysis is SepoliaConfig {

    address public owner;
    uint32 public nextSessionId;
    uint32 public totalSessions;

    struct BehaviorSession {
        euint32 sessionDuration; // encrypted session duration in minutes
        euint8 activityLevel; // encrypted activity level (0-100)
        euint8 interactionType; // encrypted interaction type (0-10)
        euint16 dataPoints; // encrypted number of data points collected
        bool isActive;
        uint256 timestamp;
        address analyst; // who can analyze this session
    }

    struct BehaviorPattern {
        euint32 avgSessionDuration;
        euint8 avgActivityLevel;
        euint8 dominantInteractionType;
        euint16 totalDataPoints;
        uint32 sessionCount;
        bool isAnalyzed;
    }

    struct PrivacyMetrics {
        euint8 privacyScore; // encrypted privacy score (0-100)
        euint8 anomalyLevel; // encrypted anomaly detection level (0-100)
        euint16 behaviorVariability; // encrypted behavior variability index
        bool requiresReview;
    }

    mapping(uint32 => BehaviorSession) public behaviorSessions;
    mapping(address => BehaviorPattern) public userPatterns;
    mapping(address => PrivacyMetrics) public privacyMetrics;
    mapping(address => bool) public authorizedAnalysts;
    mapping(address => uint32[]) public userSessions;

    event SessionRecorded(uint32 indexed sessionId, address indexed user, uint256 timestamp);
    event PatternAnalyzed(address indexed user, address indexed analyst);
    event PrivacyMetricsUpdated(address indexed user, uint256 timestamp);
    event AnomalyDetected(address indexed user, uint32 indexed sessionId);
    event AnalystAuthorized(address indexed analyst, address indexed authorizer);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    modifier onlyAuthorizedAnalyst() {
        require(authorizedAnalysts[msg.sender] || msg.sender == owner, "Not authorized analyst");
        _;
    }

    constructor() {
        owner = msg.sender;
        nextSessionId = 1;
        totalSessions = 0;
        authorizedAnalysts[msg.sender] = true;
    }

    function authorizeAnalyst(address analyst) external onlyOwner {
        authorizedAnalysts[analyst] = true;
        emit AnalystAuthorized(analyst, msg.sender);
    }

    function revokeAnalyst(address analyst) external onlyOwner {
        authorizedAnalysts[analyst] = false;
    }

    function recordBehaviorSession(
        uint32 _sessionDuration,
        uint8 _activityLevel,
        uint8 _interactionType,
        uint16 _dataPoints
    ) external {
        require(_activityLevel <= 100, "Activity level must be 0-100");
        require(_interactionType <= 10, "Interaction type must be 0-10");

        // Encrypt the behavior data
        euint32 encryptedDuration = FHE.asEuint32(_sessionDuration);
        euint8 encryptedActivity = FHE.asEuint8(_activityLevel);
        euint8 encryptedInteraction = FHE.asEuint8(_interactionType);
        euint16 encryptedDataPoints = FHE.asEuint16(_dataPoints);

        uint32 sessionId = nextSessionId;

        behaviorSessions[sessionId] = BehaviorSession({
            sessionDuration: encryptedDuration,
            activityLevel: encryptedActivity,
            interactionType: encryptedInteraction,
            dataPoints: encryptedDataPoints,
            isActive: true,
            timestamp: block.timestamp,
            analyst: address(0)
        });

        userSessions[msg.sender].push(sessionId);

        // Grant access permissions
        FHE.allowThis(encryptedDuration);
        FHE.allowThis(encryptedActivity);
        FHE.allowThis(encryptedInteraction);
        FHE.allowThis(encryptedDataPoints);

        FHE.allow(encryptedDuration, msg.sender);
        FHE.allow(encryptedActivity, msg.sender);
        FHE.allow(encryptedInteraction, msg.sender);
        FHE.allow(encryptedDataPoints, msg.sender);

        nextSessionId++;
        totalSessions++;

        emit SessionRecorded(sessionId, msg.sender, block.timestamp);

        // Update user patterns
        _updateUserPattern(msg.sender);

        // Check for anomalies
        _checkForAnomalies(msg.sender, sessionId);
    }

    function assignAnalystToSession(uint32 sessionId, address analyst) external onlyOwner {
        require(authorizedAnalysts[analyst], "Analyst not authorized");
        require(behaviorSessions[sessionId].isActive, "Session not active");

        behaviorSessions[sessionId].analyst = analyst;

        // Grant analyst access to encrypted data
        BehaviorSession storage session = behaviorSessions[sessionId];
        FHE.allow(session.sessionDuration, analyst);
        FHE.allow(session.activityLevel, analyst);
        FHE.allow(session.interactionType, analyst);
        FHE.allow(session.dataPoints, analyst);
    }

    function analyzeBehaviorPattern(address user) external onlyAuthorizedAnalyst {
        require(userSessions[user].length > 0, "No sessions for user");

        BehaviorPattern storage pattern = userPatterns[user];
        pattern.sessionCount = uint32(userSessions[user].length);
        pattern.isAnalyzed = true;

        // Grant analyst access to pattern data
        FHE.allow(pattern.avgSessionDuration, msg.sender);
        FHE.allow(pattern.avgActivityLevel, msg.sender);
        FHE.allow(pattern.dominantInteractionType, msg.sender);
        FHE.allow(pattern.totalDataPoints, msg.sender);

        emit PatternAnalyzed(user, msg.sender);
    }

    function updatePrivacyMetrics(
        address user,
        uint8 _privacyScore,
        uint8 _anomalyLevel,
        uint16 _behaviorVariability
    ) external onlyAuthorizedAnalyst {
        require(_privacyScore <= 100, "Privacy score must be 0-100");
        require(_anomalyLevel <= 100, "Anomaly level must be 0-100");

        euint8 encryptedPrivacyScore = FHE.asEuint8(_privacyScore);
        euint8 encryptedAnomalyLevel = FHE.asEuint8(_anomalyLevel);
        euint16 encryptedVariability = FHE.asEuint16(_behaviorVariability);

        privacyMetrics[user] = PrivacyMetrics({
            privacyScore: encryptedPrivacyScore,
            anomalyLevel: encryptedAnomalyLevel,
            behaviorVariability: encryptedVariability,
            requiresReview: _anomalyLevel > 70
        });

        // Grant access permissions
        FHE.allowThis(encryptedPrivacyScore);
        FHE.allowThis(encryptedAnomalyLevel);
        FHE.allowThis(encryptedVariability);

        FHE.allow(encryptedPrivacyScore, user);
        FHE.allow(encryptedAnomalyLevel, user);
        FHE.allow(encryptedVariability, user);
        FHE.allow(encryptedPrivacyScore, msg.sender);
        FHE.allow(encryptedAnomalyLevel, msg.sender);
        FHE.allow(encryptedVariability, msg.sender);

        emit PrivacyMetricsUpdated(user, block.timestamp);
    }

    function _updateUserPattern(address user) private {
        uint32[] memory sessions = userSessions[user];
        if (sessions.length == 0) return;

        // Initialize pattern if first session
        if (!userPatterns[user].isAnalyzed) {
            BehaviorSession storage firstSession = behaviorSessions[sessions[0]];
            userPatterns[user] = BehaviorPattern({
                avgSessionDuration: firstSession.sessionDuration,
                avgActivityLevel: firstSession.activityLevel,
                dominantInteractionType: firstSession.interactionType,
                totalDataPoints: firstSession.dataPoints,
                sessionCount: 1,
                isAnalyzed: false
            });
        }
    }

    function _checkForAnomalies(address user, uint32 sessionId) private {
        // Simple anomaly detection - could be enhanced with ML models
        uint32[] memory sessions = userSessions[user];
        if (sessions.length < 3) return; // Need minimum sessions for comparison

        // For now, mark as anomaly detection placeholder
        // In real implementation, this would use FHE operations to compare patterns
        emit AnomalyDetected(user, sessionId);
    }

    function getUserSessionCount(address user) external view returns (uint32) {
        return uint32(userSessions[user].length);
    }

    function getSessionInfo(uint32 sessionId) external view returns (
        bool isActive,
        uint256 timestamp,
        address analyst
    ) {
        BehaviorSession storage session = behaviorSessions[sessionId];
        return (
            session.isActive,
            session.timestamp,
            session.analyst
        );
    }

    function isAuthorizedAnalyst(address analyst) external view returns (bool) {
        return authorizedAnalysts[analyst];
    }

    function getContractStats() external view returns (
        uint32 totalSessionsCount,
        uint32 nextSessionIdValue
    ) {
        return (totalSessions, nextSessionId);
    }

    function requestDecryptedAnalysis(address user) external onlyAuthorizedAnalyst {
        require(userPatterns[user].isAnalyzed, "Pattern not analyzed");

        BehaviorPattern storage pattern = userPatterns[user];
        PrivacyMetrics storage metrics = privacyMetrics[user];

        // Request decryption for analysis
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = FHE.toBytes32(pattern.avgSessionDuration);

        FHE.requestDecryption(cts, this.processAnalysisResult.selector);
    }

    function processAnalysisResult(
        uint256 requestId,
        bytes memory cleartexts,
        bytes memory decryptionProof
    ) external {
        // Verify signatures
        FHE.checkSignatures(requestId, cleartexts, decryptionProof);

        // Decode the cleartexts to get the avgDuration
        uint32 avgDuration = abi.decode(cleartexts, (uint32));

        // Process the decrypted analysis results
        // This would typically trigger further analysis or reporting
    }
}