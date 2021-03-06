pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

/**
 * @author Enigma
 *
 * Registers events to be emitted by the various functionalities of the Enigma codebase (need to be detailed here
 * as well as in the individual library as well
 */
contract EnigmaEvents {
    event Registered(address custodian, address signer);
    event WorkersParameterized(uint seed, uint256 firstBlockNumber, uint256 inclusionBlockNumber, address[] workers,
        uint[] stakes, uint nonce);
    event TaskRecordCreated(bytes32 taskId, bytes32 inputsHash, uint64 gasLimit, uint64 gasPx, address sender,
        uint blockNumber);
    event ReceiptVerified(bytes32 taskId, bytes32 stateDeltaHash, bytes32 outputHash, bytes32 scAddr, uint gasUsed,
        uint deltaHashIndex, bytes optionalEthereumData, address optionalEthereumContractAddress, address workerAddress,
        bytes sig);
    event ReceiptFailed(bytes32 taskId, bytes sig);
    event ReceiptFailedETH(bytes32 taskId, bytes sig);
    event TaskFeeReturned(bytes32 taskId);
    event DepositSuccessful(address from, uint value);
    event WithdrawSuccessful(address to, uint value);
    event SecretContractDeployed(bytes32 scAddr, bytes32 codeHash, bytes32 initStateDeltaHash);
}
