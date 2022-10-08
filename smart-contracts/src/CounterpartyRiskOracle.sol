// @title CounterPartyRiskOracle
// @notice Provides functions to verify off chain information about counter party risk in txs
// @author Anibal Catalan <anibal@notabene.id>
pragma solidity ^0.8.17;

import "@src/ICounterpartyRiskOracle.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CounterpartyRiskOracle is ICounterpartyRiskOracle, Ownable {

    // Events
    event CounterpartyRiskAttestation(address indexed _customerVASP, address indexed _originator, address indexed _beneficiary, string _symbol, uint256 _amount);

    address private signer;

    // Notabene txHash to source to verified
    mapping (bytes32 =>  bytes) private signatureOfHash; 

    // Domain Hash
    bytes32 private immutable eip712DomainHash;

    // Type Hash
    bytes32 private constant CRA_TYPEHASH = keccak256("Counter Party Risk Attestation(address VASPAddress, address originator, address beneficiary, string symbol, uint256 amount, uint256 expireAt)");

    constructor(address _signer) {
        require(_signer != address(0), "CRO: Please use a non 0 address");
        signer = _signer;
        eip712DomainHash = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Counter Party Risk Oracle")), // ERC-721 Name
                keccak256(bytes("1")), // Version
                block.chainid,
                address(this)
            )
        );
    }
    
    // External Functions

    function verifyCounterpartyRisk(CRA memory _msg, bytes calldata _sig) external {
        require(_msg.expireAt > block.timestamp, "CRO: Deadline expired");
        require(_msg.VASPAddress == _msg.originator || _msg.VASPAddress == _msg.beneficiary, "CRO: Invalid customer VASP");
        address vasp;
        _msg.VASPAddress == _msg.originator ? vasp = _msg.originator : vasp = _msg.beneficiary;
        require(vasp == msg.sender, "CRO: Invalid sender");
        bytes32 hashedStruct = _getStructHash(_msg);
        require(signatureOfHash[hashedStruct].length == 0, "CRO: Already verified by the customer VASP");    
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_sig);
        address signer_ = _verifyMessage(eip712DomainHash, hashedStruct, v, r, s);
        require(signer_ == signer, "CRO: Invalid signature");
        require(signer_ != address(0), "ECDSA: Invalid signature");  

        signatureOfHash[hashedStruct] = _sig;
        emit CounterpartyRiskAttestation(_msg.VASPAddress, _msg.originator, _msg.beneficiary, _msg.symbol, _msg.amount);
    }

    // Setters
    function setSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "CRO: Please use a non 0 address");
        signer = _signer;
    }

    // Getters
    function getSigner() view external returns (address) {
        return signer;
    }

    function hashSignature(bytes32 _sigHash) view external returns (bytes memory) {
        return signatureOfHash[_sigHash];
    }

    function getDomainHash() view external returns (bytes32) {
        return eip712DomainHash;
    }

    // Internal Functions

    function _getStructHash(CRA memory _msg) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            CRA_TYPEHASH,
            _msg.VASPAddress,
            _msg.originator,
            _msg.beneficiary,
            _msg.symbol,
            _msg.amount,
            _msg.expireAt
        ));
    }

    function _verifyMessage(bytes32 _eip712DomainHash, bytes32 _hashedStruct, uint8 _v, bytes32 _r, bytes32 _s) internal pure returns (address) {
        //bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory prefix = "\x19\x01";
        bytes32 prefixedHashMessage = keccak256(abi.encodePacked(prefix, _eip712DomainHash, _hashedStruct));
        address signer_ = ecrecover(prefixedHashMessage, _v, _r, _s);
        return signer_;
    }

    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "CRO: Invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }
}

