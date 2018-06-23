const RLP = require ('rlp');
const abi = require ('ethereumjs-abi');
const engUtils = require ('../lib/enigma-utils');
const data = require ('./data');

// This could use the injected web3Utils
// But I don't like injected things and this ensures compatibility
// with Truffle upgrades
const web3Utils = require ('web3-utils');

const ENG_SUPPLY = 15000000000000000;

console.log ('testing the enigma lib:', engUtils.test ());

const Enigma = artifacts.require ("./contracts/Enigma.sol");
const EnigmaToken = artifacts.require ("./contracts/EnigmaToken.sol");
const CoinMixer = artifacts.require ("./contracts/CoinMixer.sol");

// Initialize contract variables
let enigma;
let engToken;
let coinMixer;
contract ('Enigma', accounts => {
    it ("...registering new worker", () => Enigma.deployed ().then (instance => {
        enigma = instance;

        let promises = [];
        for (let i = 0; i < accounts.length; i++) {
            const reportArgs = [
                data.worker[2],
                data.worker[3],
                data.worker[4],
                data.worker[5]
            ];
            const report = engUtils.rlpEncode (reportArgs);
            const quote = engUtils.rlpEncode (data.worker[1]);
            // Using the same artificial data for all workers
            let promise = enigma.register (accounts[0], quote, report, { from: accounts[i] });

            promises.push (promise);
        }
        // Using the account as the signer for testing purposes
        return Promise.all (promises);
    }).then (results => {
        results.forEach ((result) => {
            event = result.logs[0];
            // console.log (event);
            assert.equal (event.args._success, true, "Worker registration failed.");
        });
    }));

    it ("...my worker details", () => Enigma.deployed ().then (instance => {
        enigma = instance;

        return enigma.workers (accounts[0], { from: accounts[0] });
    }).then (result => {
        // console.log ('my worker details', result);
        assert.equal (result[0], accounts[0], "No worker details.");
    }));

    const callable = 'mixAddresses(uint,address[],uint)';
    const callback = 'distribute(uint32,address[])';
    const args = [
        0, [
            '01dd68b96c0a3704f006e419425aca9bcddc5704e3595c29750014733bf756e966debc595a44fa6f83a40e62292c1bbaf610a7935e8a04b3370d64728737dca24dce8f20d995239d86af034ccf3261f97b8137b972',
            '01dd68b96c0a3704f006e419425aca9bcddc5704e3595c29750014733bf756e966debc595a44fa6f83a40e62292c1bbaf610a7935e8a04b3370d64728737dca24dce8f20d995239d86af034ccf3261f97b8137b972'
        ]
    ];
    const callableArgs = '0x' + RLP.encode (args).toString ('hex');
    let taskId;
    let blockNumber;
    it ("...generate task id", () => Enigma.deployed ()
        .then (instance => {
            enigma = instance;
            return CoinMixer.deployed ();
        }).then (instance => {
            coinMixer = instance;
            return web3.eth.getBlockNumber ();
        })
        .then (_blockNumber => {
            blockNumber = _blockNumber;

            return enigma.generateTaskId.call (coinMixer.address, callable, callableArgs, blockNumber, { from: accounts[0] })
        })
        .then (contractTaskId => {
            // TODO: add to enigma-js
            taskId = engUtils.generateTaskId (coinMixer.address, callable, callableArgs, blockNumber);
            // console.log ('the task id: ', contractTaskId, taskId);
            assert.equal (contractTaskId, taskId, 'Local hash does not match contract.')
        })
    );

    it ("...executing computation", () => Enigma.deployed ()
        .then (instance => {
            enigma = instance;
            return EnigmaToken.deployed ();
        })
        .then (instance => {
            engToken = instance;
            return CoinMixer.deployed ();
        })
        .then (instance => {
            coinMixer = instance;
            return engToken.totalSupply ();
        })
        .then (supply => {
            assert.equal (supply, ENG_SUPPLY, 'Invalid ENG total supply.');

            return engToken.balanceOf (accounts[0]);
        })
        .then (balance => {
            assert.equal (balance, ENG_SUPPLY, 'Invalid account ENG balance.');
            return engToken.approve (enigma.address, 1, { from: accounts[0] })
        })
        .then (result => {
            let event = result.logs[0];
            assert.equal (event.event, 'Approval', 'Approval failed.');

            return engToken.allowance (accounts[0], enigma.address);
        })
        .then (allowance => {
            assert.equal (allowance, 1, "Incorrect allowance.");

            // RLP encoding arguments
            const preprocessor = [web3Utils.utf8ToHex ('rand()')];
            return enigma.compute (
                coinMixer.address, callable, callableArgs, callback, 1, preprocessor, blockNumber,
                { from: accounts[0] }
            );
        }).then (result => {
            let event = result.logs[0];
            // console.log ('secret call event', event);

            assert.equal (event.args._success, true, "Unable to compute.");
        }));

    it ("...querying task", () => Enigma.deployed ()
        .then (instance => {
            enigma = instance;
            return CoinMixer.deployed ();
        })
        .then (instance => {
            coinMixer = instance;
            return enigma.tasks (taskId, { from: accounts[0] });
        }).then (task => {
            assert.equal (task[0], coinMixer.address, "Task not found.");
        }));

    // Changing a character in one of the two results should break the validation
    const localResults = [
        0, [
            web3Utils.toChecksumAddress ('0x6330a553fc93768f612722bb8c2ec78ac90b3bbc'),
            web3Utils.toChecksumAddress ('0x5aeda56215b167893e80b4fe645ba6d5bab767de')
        ]
    ];
    const contractResults = [
        0, [
            web3Utils.toChecksumAddress ('0x6330a553fc93768f612722bb8c2ec78ac90b3bbc'),
            web3Utils.toChecksumAddress ('0x5aeda56215b167893e80b4fe645ba6d5bab767de')
        ]
    ];
    it ("...committing results", () => Enigma.deployed ()
        .then (instance => {
            enigma = instance;

            return CoinMixer.deployed ();
        })
        .then (instance => {
            coinMixer = instance;

            const encodedArgs = '0x' + RLP.encode (args).toString ('hex');

            const fName = callback.substr (0, callback.indexOf ('('));
            assert.equal (fName, 'distribute', 'Function name parsed incorrectly');

            const rx = /distribute\((.*)\)/g;
            const resultArgs = rx.exec (callback)[1].split (',');
            assert.equal (JSON.stringify (resultArgs), JSON.stringify (['uint32', 'address[]']));
            //
            const functionId = web3Utils.soliditySha3 ({
                t: 'string',
                v: callback
            }).slice (0, 10);
            const localData = functionId + abi.rawEncode (resultArgs, localResults).toString ('hex');

            return web3.eth.getCode (coinMixer.address).then ((bytecode) => {
                // The holy grail, behaves exactly as keccak256() in Solidity
                const hash = web3Utils.soliditySha3 (encodedArgs, localData, bytecode);
                const contractData = functionId + abi.rawEncode (resultArgs, contractResults).toString ('hex');

                // Using an actual Ethereum address instead of a virtual address
                // This is testing the same thing
                // The python unit tests handle virtual addresses from private keys.
                return web3.eth.sign (hash, accounts[0]).then ((sig) => {
                    return enigma.commitResults (taskId, contractData, sig, { from: accounts[0] });
                });
            });

        })
        .then (result => {
            // console.log ('the commit results', result);
            let event1 = result.logs[0];
            let event2 = result.logs[1];
            // console.log ('commit results event', event2);

            assert.equal (event1.args._success, true, 'Unable to verify hash.');
            assert.equal (event2.args._success, true, 'Unable to commit results.');
        }));

    let lastFiveWorkers = [];
    it ("...it setting workers params", () => {
        return Enigma.deployed ().then (instance => {
            enigma = instance;

            let promises = [];
            for (let i = 0; i < 10; i++) {
                const seed = Math.floor (Math.random () * 100000);
                const hash = web3Utils.soliditySha3 (
                    { t: 'uint256', v: seed }
                );
                let promise = web3.eth.sign (hash, accounts[0]).then ((sig) => {
                    return enigma.setWorkersParams (seed, sig, { from: accounts[0] });
                });
                promises.push (promise);
            }
            return Promise.all (promises);
        }).then (results => {
            results.forEach ((result, i) => {
                let event = result.logs[0];
                assert.equal (event.args._success, true, 'Unable to parameterize workers.');
                if (i > 4) {
                    lastFiveWorkers.push ({
                        seed: parseInt (event.args.seed),
                        blockNumber: event.blockNumber
                    });
                }
            });
            // console.log ('last five workers', JSON.stringify (lastFiveWorkers));
        });
    });

    it ("...it getting workers params", () => {
        return Enigma.deployed ().then (instance => {
            enigma = instance;

            let promises = [];
            lastFiveWorkers.forEach ((worker) => {
                promises.push (enigma.getWorkersParams (worker.blockNumber, { from: accounts[0] }));
            });
            return Promise.all (promises);
        }).then (results => {
            let workerParams = [];
            results.forEach ((result) => {
                // console.log('the worker params', JSON.stringify(result))
                workerParams.push ({
                    seed: parseInt (result[1]),
                    blockNumber: parseInt (result[0])
                });
            });
            // console.log ('workers parameters', workerParams);
            assert.equal (JSON.stringify (lastFiveWorkers), JSON.stringify (workerParams), "worker params don't match calculated list");
        });
    });

    let selectedBlock;
    let selectedWorker;
    const workerIndex = Math.floor (Math.random () * 4);
    it ("...it selecting worker " + workerIndex, () => {
        return Enigma.deployed ().then (instance => {
            enigma = instance;

            selectedBlock = lastFiveWorkers[workerIndex].blockNumber;
            return enigma.getWorkersParams (selectedBlock, { from: accounts[0] });
        }).then (result => {
            const workerParams = {
                seed: result[1],
                blockNumber: result[0],
                workers: result[2].filter (addr => addr > 0)
            };

            // console.log ('worker params:', JSON.stringify (workerParams));
            selectedWorker = engUtils.selectWorker (workerParams.seed, taskId, workerParams.workers);
            // console.log ('the selected worker:', selectedWorker, workerParams.seed, workerParams.workers.length);
            return enigma.selectWorker (selectedBlock, taskId, { from: accounts[0] });
        }).then (contractSelectedWorker => {

            // console.log ('the contract selected worker:', contractSelectedWorker);
            assert.equal (contractSelectedWorker, selectedWorker, "Selected worker does not match");
        });
    });

    it ("...verifying the worker's signature and certificate", () => {
        return Enigma.deployed ().then (instance => {
            enigma = instance;

            return enigma.getReport (accounts[0], { from: accounts[0] });
        }).then (result => {

            const response = engUtils.verifyWorker (result[0], result[1]);
            assert (response.verified, "Verification failed");
        });

    })
});
