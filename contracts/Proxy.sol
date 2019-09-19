import { EnigmaStorage } from "./impl/EnigmaStorage.sol";
import { ERC20 } from "./interfaces/ERC20.sol";

contract Proxy is EnigmaStorage {

    modifier onlyOwner() {
        require (msg.sender == state.owner);
        _;
    }

    /**
     * @dev constructor that sets the owner address
     */
    constructor(address _tokenAddress, address _principal, uint _epochSize) public {
        state.owner = msg.sender;
        state.engToken = ERC20(_tokenAddress);
        state.epochSize = _epochSize;
        state.taskTimeoutSize = 200;
        state.principal = _principal;
        state.stakingThreshold = 1;
        state.workerGroupSize = 1;
    }

    function getAddress() public view returns (address){
        return state.implementation;
    }

    /**
     * @dev Upgrades the implementation address
     * @param _newImplementation address of the new implementation
     */
    function upgradeTo(address _newImplementation)
    external onlyOwner
    {
        require(state.implementation != _newImplementation);
        _setImplementation(_newImplementation);
    }

    /**
     * @dev Fallback function allowing to perform a delegatecall
     * to the given implementation. This function will return
     * whatever the implementation call returns
     */
    function () payable external {
        address impl = state.implementation;
        require(impl != address(0));
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize)
            let result := delegatecall(gas, impl, ptr, calldatasize, 0, 0)
            let size := returndatasize
            returndatacopy(ptr, 0, size)

            switch result
            case 0 { revert(ptr, size) }
            default { return(ptr, size) }
        }
    }

    /**
     * @dev Sets the address of the current implementation
     * @param _newImp address of the new implementation
     */
    function _setImplementation(address _newImp) internal {
        state.implementation = _newImp;
    }
}