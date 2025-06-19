// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // Struct to represent a skill verification
    struct SkillVerification {
        string skillName;
        address verifier;
        uint256 stakeAmount;
        uint256 timestamp;
        bool isActive;
        uint8 proficiencyLevel; // 1-10 scale
    }
    
    // Struct to represent a bounty/job posting
    struct Bounty {
        uint256 bountyId;
        address creator;
        string requiredSkill;
        uint8 minProficiencyLevel;
        uint256 reward;
        string description;
        address assignedTo;
        bool isCompleted;
        bool isPaid;
        uint256 deadline;
    }
    
    // Struct to track user reputation and skills
    struct UserProfile {
        uint256 totalStaked;
        uint256 successfulCompletions;
        uint256 reputationScore;
        string[] verifiedSkills;
        bool isActive;
    }
    
    // State variables
    mapping(address => UserProfile) public userProfiles;
    mapping(address => mapping(string => SkillVerification)) public skillVerifications;
    mapping(uint256 => Bounty) public bounties;
    mapping(address => uint256[]) public userBounties;
    
    uint256 public nextBountyId = 1;
    uint256 public constant MIN_STAKE_AMOUNT = 0.01 ether;
    uint256 public constant VERIFICATION_PERIOD = 7 days;
    
    // Events
    event SkillVerified(address indexed user, string skill, address indexed verifier, uint8 proficiencyLevel);
    event BountyCreated(uint256 indexed bountyId, address indexed creator, string requiredSkill, uint256 reward);
    event BountyAssigned(uint256 indexed bountyId, address indexed assignee);
    event BountyCompleted(uint256 indexed bountyId, address indexed assignee, uint256 reward);
    event StakeSlashed(address indexed user, string skill, uint256 amount);
    
    // Modifiers
    modifier onlyVerifiedForSkill(string memory skill) {
        require(
            skillVerifications[msg.sender][skill].isActive &&
            skillVerifications[msg.sender][skill].timestamp + VERIFICATION_PERIOD > block.timestamp,
            "Skill not verified or verification expired"
        );
        _;
    }
    
    modifier validBounty(uint256 bountyId) {
        require(bountyId > 0 && bountyId < nextBountyId, "Invalid bounty ID");
        require(bounties[bountyId].creator != address(0), "Bounty does not exist");
        _;
    }
    
    // Core Function 1: Verify and stake on skills
    function verifySkill(
        address user,
        string memory skillName,
        uint8 proficiencyLevel
    ) external payable {
        require(msg.value >= MIN_STAKE_AMOUNT, "Insufficient stake amount");
        require(proficiencyLevel >= 1 && proficiencyLevel <= 10, "Invalid proficiency level");
        require(user != msg.sender, "Cannot verify your own skills");
        require(bytes(skillName).length > 0, "Skill name cannot be empty");
        
        // Create or update skill verification
        skillVerifications[user][skillName] = SkillVerification({
            skillName: skillName,
            verifier: msg.sender,
            stakeAmount: msg.value,
            timestamp: block.timestamp,
            isActive: true,
            proficiencyLevel: proficiencyLevel
        });
        
        // Update user profile
        UserProfile storage profile = userProfiles[user];
        profile.totalStaked += msg.value;
        profile.reputationScore += proficiencyLevel;
        
        // Add skill to verified skills list if not already present
        bool skillExists = false;
        for (uint i = 0; i < profile.verifiedSkills.length; i++) {
            if (keccak256(bytes(profile.verifiedSkills[i])) == keccak256(bytes(skillName))) {
                skillExists = true;
                break;
            }
        }
        if (!skillExists) {
            profile.verifiedSkills.push(skillName);
        }
        
        profile.isActive = true;
        
        emit SkillVerified(user, skillName, msg.sender, proficiencyLevel);
    }
    
    // Core Function 2: Create bounty for specific skills
    function createBounty(
        string memory requiredSkill,
        uint8 minProficiencyLevel,
        string memory description,
        uint256 durationInDays
    ) external payable {
        require(msg.value > 0, "Bounty reward must be greater than 0");
        require(minProficiencyLevel >= 1 && minProficiencyLevel <= 10, "Invalid proficiency level");
        require(bytes(requiredSkill).length > 0, "Required skill cannot be empty");
        require(durationInDays > 0 && durationInDays <= 365, "Invalid duration");
        
        uint256 bountyId = nextBountyId++;
        
        bounties[bountyId] = Bounty({
            bountyId: bountyId,
            creator: msg.sender,
            requiredSkill: requiredSkill,
            minProficiencyLevel: minProficiencyLevel,
            reward: msg.value,
            description: description,
            assignedTo: address(0),
            isCompleted: false,
            isPaid: false,
            deadline: block.timestamp + (durationInDays * 1 days)
        });
        
        emit BountyCreated(bountyId, msg.sender, requiredSkill, msg.value);
    }
    
    // Core Function 3: Complete bounty and distribute rewards
    function completeBounty(uint256 bountyId) external validBounty(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.assignedTo == msg.sender, "You are not assigned to this bounty");
        require(!bounty.isCompleted, "Bounty already completed");
        require(block.timestamp <= bounty.deadline, "Bounty deadline exceeded");
        
        // Verify user still has required skill verification
        SkillVerification storage verification = skillVerifications[msg.sender][bounty.requiredSkill];
        require(verification.isActive, "Skill verification is not active");
        require(verification.proficiencyLevel >= bounty.minProficiencyLevel, "Insufficient proficiency level");
        require(verification.timestamp + VERIFICATION_PERIOD > block.timestamp, "Skill verification expired");
        
        // Mark bounty as completed
        bounty.isCompleted = true;
        bounty.isPaid = true;
        
        // Update user reputation
        UserProfile storage profile = userProfiles[msg.sender];
        profile.successfulCompletions++;
        profile.reputationScore += 10; // Bonus points for completion
        
        // Transfer reward to the user
        payable(msg.sender).transfer(bounty.reward);
        
        emit BountyCompleted(bountyId, msg.sender, bounty.reward);
    }
    
    // Helper function to assign bounty to qualified user
    function assignBounty(uint256 bountyId, address assignee) external validBounty(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.creator, "Only bounty creator can assign");
        require(bounty.assignedTo == address(0), "Bounty already assigned");
        require(block.timestamp < bounty.deadline, "Bounty expired");
        
        // Verify assignee has required skill
        SkillVerification storage verification = skillVerifications[assignee][bounty.requiredSkill];
        require(verification.isActive, "Assignee does not have verified skill");
        require(verification.proficiencyLevel >= bounty.minProficiencyLevel, "Assignee proficiency too low");
        require(verification.timestamp + VERIFICATION_PERIOD > block.timestamp, "Skill verification expired");
        
        bounty.assignedTo = assignee;
        userBounties[assignee].push(bountyId);
        
        emit BountyAssigned(bountyId, assignee);
    }
    
    // Function to get user's verified skills
    function getUserSkills(address user) external view returns (string[] memory) {
        return userProfiles[user].verifiedSkills;
    }
    
    // Function to get user's bounties
    function getUserBounties(address user) external view returns (uint256[] memory) {
        return userBounties[user];
    }
    
    // Function to get skill verification details
    function getSkillVerification(address user, string memory skill) 
        external view returns (SkillVerification memory) {
        return skillVerifications[user][skill];
    }
    
    // Function to check if skill verification is still valid
    function isSkillVerificationValid(address user, string memory skill) 
        external view returns (bool) {
        SkillVerification storage verification = skillVerifications[user][skill];
        return verification.isActive && 
               verification.timestamp + VERIFICATION_PERIOD > block.timestamp;
    }
    
    // Emergency function to slash stake for fraudulent verification
    function slashStake(address user, string memory skill) external {
        SkillVerification storage verification = skillVerifications[user][skill];
        require(verification.verifier == msg.sender, "Only verifier can slash stake");
        require(verification.isActive, "Skill verification not active");
        
        uint256 slashAmount = verification.stakeAmount;
        verification.isActive = false;
        verification.stakeAmount = 0;
        
        // Update user profile
        userProfiles[user].totalStaked -= slashAmount;
        if (userProfiles[user].reputationScore >= verification.proficiencyLevel) {
            userProfiles[user].reputationScore -= verification.proficiencyLevel;
        }
        
        // Transfer slashed amount to verifier (as penalty for false verification)
        payable(msg.sender).transfer(slashAmount);
        
        emit StakeSlashed(user, skill, slashAmount);
    }
}
