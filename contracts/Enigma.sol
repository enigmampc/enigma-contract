pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/cryptography/ECDSA.sol";
import "./utils/SolRsaVerify.sol";

import { WorkersImpl } from "./impl/WorkersImpl.sol";
import { PrincipalImpl } from "./impl/PrincipalImpl.sol";
import { TaskImpl } from "./impl/TaskImpl.sol";
import { SecretContractImpl } from "./impl/SecretContractImpl.sol";
import { EnigmaCommon } from "./impl/EnigmaCommon.sol";
import { EnigmaState } from "./impl/EnigmaState.sol";
import { EnigmaEvents } from "./impl/EnigmaEvents.sol";
import { EnigmaStorage } from "./impl/EnigmaStorage.sol";
import { Getters } from "./impl/Getters.sol";
import { ERC20 } from "./interfaces/ERC20.sol";

contract Enigma is EnigmaStorage, EnigmaEvents, Getters {
    using SafeMath for uint256;
    using ECDSA for bytes32;

    // ========================================== Constructor ==========================================

    constructor(address _tokenAddress, address _principal, uint _epochSize, uint _timeoutThreshold) public {
        state.engToken = ERC20(_tokenAddress);
        state.epochSize = _epochSize;
        state.taskTimeoutSize = _timeoutThreshold * state.epochSize;
        state.principal = _principal;
        state.stakingThreshold = 1;
        state.workerGroupSize = 1;
    }

    // ========================================== Modifiers ==========================================

    /**
    * Checks if the custodian wallet is registered as a worker
    *
    * @param _user The custodian address of the worker
    */
    modifier workerRegistered(address _user) {
        EnigmaCommon.Worker memory worker = state.workers[_user];
        require(worker.status != EnigmaCommon.WorkerStatus.Unregistered, "Unregistered worker");
        _;
    }

    /**
    * Checks if the custodian wallet is logged in as a worker
    *
    * @param _user The custodian address of the worker
    */
    modifier workerLoggedIn(address _user) {
        EnigmaCommon.Worker memory worker = state.workers[_user];
        require(worker.status == EnigmaCommon.WorkerStatus.LoggedIn, "Worker not logged in");
        _;
    }

    /**
    * Checks if the custodian wallet is logged out as a worker
    *
    * @param _user The custodian address of the worker
    */
    modifier workerLoggedOut(address _user) {
        EnigmaCommon.Worker memory worker = state.workers[_user];
        require(worker.status == EnigmaCommon.WorkerStatus.LoggedOut, "Worker not logged out");
        _;
    }

    /**
    * Checks if worker can log in
    *
    * @param _user The custodian address of the worker
    */
    modifier canLogIn(address _user) {
        EnigmaCommon.Worker memory worker = state.workers[_user];
        require(getFirstBlockNumber(block.number) != 0, "Principal node has not been initialized");
        require(worker.status == EnigmaCommon.WorkerStatus.LoggedOut, "Worker not registered or not logged out");
        require(worker.balance >= state.stakingThreshold, "Worker's balance is not sufficient");
        _;
    }

    /**
    * Checks if the worker can withdraw
    *
    * @param _user The custodian address of the worker
    */
    modifier canWithdraw(address _user) {
        EnigmaCommon.Worker memory worker = state.workers[_user];
        require(worker.status == EnigmaCommon.WorkerStatus.LoggedOut, "Worker not registered or not logged out");
        EnigmaCommon.WorkerLog memory workerLog = WorkersImpl.getLatestWorkerLogImpl(worker, block.number);
        require(workerLog.workerEventType == EnigmaCommon.WorkerLogType.LogOut,
            "Worker's last log is not of LogOut type");
        require(getFirstBlockNumber(block.number) > workerLog.blockNumber,
            "Cannot withdraw in same epoch as log out event");
        _;
    }

    /**
    * Checks secret contract has not been deployed
    *
    * @param _scAddr Secret contract address
    */
    modifier contractUndefined(bytes32 _scAddr) {
        require(state.contracts[_scAddr].status == EnigmaCommon.SecretContractStatus.Undefined, "Secret contract already deployed");
        _;
    }

    /**
    * Checks secret contract has been deployed
    *
    * @param _scAddr Secret contract address
    */
    modifier contractDeployed(bytes32 _scAddr) {
        require(state.contracts[_scAddr].status == EnigmaCommon.SecretContractStatus.Deployed, "Secret contract not deployed");
        _;
    }

    /**
    * Checks task record has been created and is still pending receipt
    *
    * @param _taskId Task ID
    */
    modifier taskWaiting(bytes32 _taskId) {
        require(state.tasks[_taskId].status == EnigmaCommon.TaskStatus.RecordCreated, "Task is not waiting");
        _;
    }

    /**
    * Ensure signing key used for registration is unique
    *
    * @param _signer Signing key
    */
    modifier isUniqueSigningKey(address _signer) {
        for (uint i = 0; i < state.workerAddresses.length; i++) {
            require(state.workers[state.workerAddresses[i]].signer != _signer, "Not a unique signing key");
        }
        _;
    }

    // ========================================== Functions ==========================================

    /**
    * Registers a new worker or change the signer parameters of an existing
    * worker. This should be called by every worker (and the principal)
    * node in order to receive tasks.
    *
    * @param _signer The signer address, derived from the enclave public key
    * @param _report The RLP encoded report returned by the IAS
    * @param _signature Signature
    */
    function register(address _signer, bytes memory _report, bytes memory _signature)
    public
    isUniqueSigningKey(_signer)
    {
        WorkersImpl.registerImpl(state, _signer, _report, _signature);
    }

    /**
    * Deposits ENG stake into contract from worker. Worker must be registered to do so.
    *
    * @param _custodian The worker's ETH address
    * @param _amount The amount of ENG, in grains format (10 ** 8), to deposit
    */
    function deposit(address _custodian, uint _amount)
    public
    workerRegistered(_custodian)
    {
        WorkersImpl.depositImpl(state, _custodian, _amount);
    }

    /**
    * Withdraws ENG stake from contract back to worker. Worker must be registered to do so.
    *
    * @param _amount The amount of ENG, in grains format (10 ** 8), to deposit
    */
    function withdraw(uint _amount)
    public
    canWithdraw(msg.sender)
    {
        WorkersImpl.withdrawImpl(state, _amount);
    }

    /**
    * Login worker. Worker must be registered to do so, and must be logged in at start of epoch to be part of worker
    * selection process.
    */
    function login() public canLogIn(msg.sender) {
        WorkersImpl.loginImpl(state);
    }

    /**
    * Logout worker. Worker must be logged in to do so.
    */
    function logout() public workerLoggedIn(msg.sender) {
        WorkersImpl.logoutImpl(state);
    }

    /**
    * Deploy secret contract from user, called by the worker.
    *
    * @param _taskId Task ID of corresponding deployment task (taskId == scAddr)
    * @param _codeHash Deployed bytecode hash
    * @param _gasUsed Gas used for task
    * @param _sig Worker's signature for deployment
    */
    function deploySecretContractFailure(
        bytes32 _taskId,
        bytes32 _codeHash,
        uint64 _gasUsed,
        bytes memory _sig
    )
    public
    workerLoggedIn(msg.sender)
    contractUndefined(_taskId)
    {
        TaskImpl.deploySecretContractFailureImpl(state, _taskId, _codeHash, _gasUsed, _sig);
    }

    /**
    * Deploy secret contract from user, called by the worker.
    *
    * @param _taskId Task ID of corresponding deployment task (taskId == scAddr)
    * @param _preCodeHash Predeployed bytecode hash
    * @param _codeHash Deployed bytecode hash
    * @param _initStateDeltaHash Initial state delta hash as a result of the contract's constructor
    * @param _optionalEthereumData Initial state delta hash as a result of the contract's constructor
    * @param _optionalEthereumContractAddress Initial state delta hash as a result of the contract's constructor
    * @param _gasUsed Gas used for task
    * @param _sig Worker's signature for deployment
    */
    function deploySecretContract(
        bytes32 _taskId,
        bytes32 _preCodeHash,
        bytes32 _codeHash,
        bytes32 _initStateDeltaHash,
        bytes memory _optionalEthereumData,
        address _optionalEthereumContractAddress,
        uint64 _gasUsed,
        bytes memory _sig
    )
    public
    workerLoggedIn(msg.sender)
    contractUndefined(_taskId)
    {
        TaskImpl.deploySecretContractImpl(state, _taskId, _preCodeHash, _codeHash, _initStateDeltaHash,
            _optionalEthereumData, _optionalEthereumContractAddress, _gasUsed, _sig);
    }

    /**
    * Check if secret contract has been deployed
    *
    * @return  Number of deployed secret contracts
    */
    function countSecretContracts()
    public
    view
    returns (uint)
    {
        return SecretContractImpl.countSecretContractsImpl(state);
    }

    /**
    * Get deployed secret contract addresses within a range
    *
    * @param _start Start of range
    * @param _stop End of range
    * @return Subset of deployed secret contract addresses
    */
    function getSecretContractAddresses(uint _start, uint _stop)
    public
    view
    returns (bytes32[] memory)
    {
        return SecretContractImpl.getSecretContractAddressesImpl(state, _start, _stop);
    }

    /**
    * Create task record for contract deployment. This is necessary for transferring task fee from sender to contract,
    * generating the unique taskId, saving the block number when the record was mined, and incrementing the user's
    * task deployment counter nonce. We revert the process if the locally-generated nonce value does not match
    * the on-chain-computed nonce since this indicates that the secret contract address the user has generated is
    * invalid.
    *
    * @param _inputsHash Hash of encrypted fn sig, encrypted ABI-encoded args, and predeployed bytecode hash
    * @param _gasLimit ENG gas limit
    * @param _gasPx ENG gas price in grains format (10 ** 8)
    * @param _firstBlockNumber Locally-computed first block number of epoch
    * @param _nonce Locally-computed nonce value for this deployment
    */
    function createDeploymentTaskRecord(
        bytes32 _inputsHash,
        uint64 _gasLimit,
        uint64 _gasPx,
        uint _firstBlockNumber,
        uint _nonce
    )
    public
    {
        TaskImpl.createDeploymentTaskRecordImpl(state, _inputsHash, _gasLimit, _gasPx, _firstBlockNumber, _nonce);
    }

    /**
    * Create task record for task for regular tasks. This is necessary for transferring task fee from sender to
    * contract, generating the unique taskId, saving the block number when the record was mined, and incrementing
    * the user's task deployment counter nonce.
    *
    * @param _inputsHash Hash of encrypted fn sig, encrypted ABI-encoded args, and contract address
    * @param _gasLimit ENG gas limit
    * @param _gasPx ENG gas price in grains format (10 ** 8)
    * @param _firstBlockNumber Locally-computed first block number of epoch
    */
    function createTaskRecord(
        bytes32 _inputsHash,
        uint64 _gasLimit,
        uint64 _gasPx,
        uint _firstBlockNumber
    )
    public
    {
        TaskImpl.createTaskRecordImpl(state, _inputsHash, _gasLimit, _gasPx, _firstBlockNumber);
    }

    /**
    * Commit the computation task results on chain by first verifying the receipt and then the worker's signature.
    * The task record is finalized and the worker is credited with the task fee.
    *
    * @param _scAddr Secret contract address
    * @param _taskId Unique taskId
    * @param _stateDeltaHash Input state delta hash
    * @param _outputHash Output state hash
    * @param _optionalEthereumData Output state hash
    * @param _optionalEthereumContractAddress Output state hash
    * @param _gasUsed Gas used for task computation
    * @param _sig Worker's signature
    */
    function commitReceipt(
        bytes32 _scAddr,
        bytes32 _taskId,
        bytes32 _stateDeltaHash,
        bytes32 _outputHash,
        bytes memory _optionalEthereumData,
        address _optionalEthereumContractAddress,
        uint64 _gasUsed,
        bytes memory _sig
    )
    public
    workerLoggedIn(msg.sender)
    contractDeployed(_scAddr)
    {
        TaskImpl.commitReceiptImpl(state, _scAddr, _taskId, _stateDeltaHash, _outputHash, _optionalEthereumData,
            _optionalEthereumContractAddress, _gasUsed, _sig);
    }

    /**
    * Commit the computation task failure on chain - the task fee is transfered to the worker and the status is
    * updated to indicate task failure.
    *
    * @param _scAddr Secret contract address
    * @param _taskId Unique taskId
    * @param _outputHash Output state hash
    * @param _gasUsed Gas used for task computation
    * @param _sig Worker's signature
    */
    function commitTaskFailure(
        bytes32 _scAddr,
        bytes32 _taskId,
        bytes32 _outputHash,
        uint64 _gasUsed,
        bytes memory _sig
    )
    public
    workerLoggedIn(msg.sender)
    contractDeployed(_scAddr)
    {
        TaskImpl.commitTaskFailureImpl(state, _scAddr, _taskId, _outputHash, _gasUsed, _sig);
    }

    /**
    * Return the task fee to the task creator when too many blocks have elapsed without task resolution.
    *
    * @param _taskId Unique taskId
    */
    function returnFeesForTask(bytes32 _taskId)
    public
    taskWaiting(_taskId)
    {
        TaskImpl.returnFeesForTaskImpl(state, _taskId);
    }

    /**
    * Reparameterizing workers with a new seed
    * This should be called for each epoch by the Principal node
    *
    * @param _blockNumber Block number principal node is attempting to set worker params
    * @param _seed The random integer generated by the enclave
    * @param _sig Principal node's signature
    */
    function setWorkersParams(uint _blockNumber, uint _seed, bytes memory _sig)
    public
    workerRegistered(msg.sender)
    {
        PrincipalImpl.setWorkersParamsImpl(state, _blockNumber, _seed, _sig);
    }

    /**
    * Get active workers before a certain block number
    *
    * @param _blockNumber Block number
    */
    function getActiveWorkers(uint _blockNumber)
    public
    view
    returns (address[] memory, uint[] memory)
    {
        return PrincipalImpl.getActiveWorkersImpl(state, _blockNumber);
    }

    /**
    * Get the first block number of an epoch that a given block number belongs to
    *
    * @param _blockNumber Block number
    * @return Block number
    */
    function getFirstBlockNumber(uint _blockNumber)
    public
    view
    returns (uint) {
        return WorkersImpl.getFirstBlockNumberImpl(state, _blockNumber);
    }

    /**
    * Get worker params for an epoch given a particular block number
    *
    * @param _blockNumber Block number
    * @return Epoch's first block number
    * @return Seed
    * @return Array of worker's signing addresses
    * @return Array of worker's stakes
    */
    function getWorkerParams(uint _blockNumber)
    public
    view
    returns (uint, uint, address[] memory, uint[] memory) {
        return WorkersImpl.getWorkerParamsImpl(state, _blockNumber);
    }

    /**
    * Select a group of workers for the computation task given the block number of the task record (implies the epoch)
    * and the secret contract address.
    *
    * @param _blockNumber Block number the task record was mined
    * @param _scAddr Secret contract address
    * @return Selected workers' addresses
    */
    function getWorkerGroup(uint _blockNumber, bytes32 _scAddr)
    public
    view
    returns (address[] memory)
    {
        return WorkersImpl.getWorkerGroupImpl(state, _blockNumber, _scAddr);
    }

    /**
    * The RLP encoded report returned by the IAS server
    *
    * @param _custodian The worker's custodian address
    */
    function getReport(address _custodian)
    public
    view
    workerRegistered(_custodian)
    returns (address, bytes memory)
    {
        return WorkersImpl.getReportImpl(state, _custodian);
    }

    /**
    * This verifies an IAS report with hard coded modulus and exponent of Intel's certificate.
    * @param _data The report itself
    * @param _signature The signature of the report
    */
    function verifyReport(bytes memory _data, bytes memory _signature)
    public
    view
    returns (uint)
    {
        return WorkersImpl.verifyReportImpl(_data, _signature);
    }
}
