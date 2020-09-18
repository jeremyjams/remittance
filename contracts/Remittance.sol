pragma solidity >=0.4.21 <0.7.0;

import "./Pausable.sol";

contract Remittance is Pausable {

    // bytes32 challenge => Grant grant, where challenge is the ID/puzzle of the grant required to solve for redeeming funds
    mapping(bytes32 => Grant) public grants;
    uint public constant MAX_CLAIMABLE_AFTER_N_HOURS = 24 hours;
    uint public cut;
    uint public income;

    struct Grant {
        address sender;
        uint amount;
        uint claimableDate;
    }

    event GrantEvent(bytes32 indexed challenge, address indexed sender, uint amount, uint claimableDate);
    event RedeemEvent(bytes32 indexed challenge, address indexed recipient, uint amount);
    event ClaimEvent(bytes32 indexed challenge, address indexed recipient, uint amount);
    event WithdrawIncomeEvent(address indexed owner, uint amount);

    constructor(bool _paused, uint _cut) Pausable(_paused) public {
        cut = _cut;
    }

    function generateChallenge(address redeemer, bytes32 password) public view returns (bytes32 challenge) {
        require(redeemer != address(0), "Empty redeemer");
        require(password != 0, "Empty password");

        challenge = keccak256(abi.encodePacked(address(this), redeemer, password));
    }

    /*
    * challenge is the ID of the grant
    */
    function grant(bytes32 challenge, uint8 claimableAfterNHours) public payable whenNotPaused {
        require(msg.value > cut, "Grant should be greater than our cut");
        //prevents locking bad formatted grant
        require(challenge != 0, "Empty challenge");
        //prevents reusing same secrets
        require(grants[challenge].sender == address(0), "Challenge already used by someone");
        //prevents badly formatted construction
        require(claimableAfterNHours < MAX_CLAIMABLE_AFTER_N_HOURS, "Claim period should be less than 24 hours");

        income += cut;
        uint amount = msg.value - cut;
        grants[challenge].amount = amount;
        grants[challenge].sender = msg.sender;
        grants[challenge].claimableDate = now + claimableAfterNHours * 1 hours;
        emit GrantEvent(challenge, msg.sender, amount, grants[challenge].claimableDate);
    }

    /*
    * Note: UTF8-> bytes32 conversion made by web app backend
    *
    * Remove challenge from signature? -> No, it is better to keep challenge in signature. It is more secure to keep it
    * since with it Carol would need to brut force password for all existing public challenges
    *
    */
    function redeem(bytes32 _challenge, bytes32 password) public whenNotPaused returns (bool success) {
        require(_challenge != 0, "Empty challenge");
        require(password != 0, "Empty password");
        uint amount = grants[_challenge].amount;
        require(amount > 0, "Empty grant");

        bytes32 challenge = generateChallenge(msg.sender, password);
        require(challenge == _challenge, "Invalid sender or password");

        //avoid reentrancy with non-zero amount
        grants[challenge].amount = 0;
        //dont clear grant.sender to avoid reusing same secrets
        emit RedeemEvent(challenge, msg.sender, amount);
        (success,) = msg.sender.call.value(amount)("");
        require(success, "Redeem transfer failed");
    }

    function claim(bytes32 challenge) public whenNotPaused returns (bool success) {
        require(challenge != 0, "Empty challenge");
        uint amount = grants[challenge].amount;
        require(amount > 0, "Empty grant");
        require(msg.sender == grants[challenge].sender, "Sender is not sender of grant");
        require(now >= grants[challenge].claimableDate, "Should wait claimable date");

        //see redeem() comments
        grants[challenge].amount = 0;
        emit ClaimEvent(challenge, msg.sender, amount);
        (success,) = msg.sender.call.value(amount)("");
        require(success, "Claim transfer failed");
    }

    /*
     * Income goes to current owner
     */
    function withdrawIncome() public onlyOwner whenNotPaused returns (bool success) {
        require(income > 0, "Empty income");
        uint amount = income;
        income = 0;
        emit WithdrawIncomeEvent(msg.sender, amount);
        (success,) = msg.sender.call.value(amount)("");
        require(success, "WithdrawIncome transfer failed");
    }

}
