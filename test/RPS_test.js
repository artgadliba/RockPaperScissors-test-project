const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RockPaperScissors contract", function () {

  let addr1;
  let addr2;
  let rps;
  let RockPaperScissors;
  let player1;
  let player2;
  let secretMove_p1;
  let secretMove_p2;
  let gameId;

  beforeEach(async function () {

    RockPaperScissors = await ethers.getContractFactory("RockPaperScissors");
    rps = await RockPaperScissors.deploy();
    await rps.deployed();
    [addr1, addr2] = await ethers.getSigners();

    player1 = {
      move: 1,
      seed: "Frodo Beggins"
    };

    player2 = {
      move: 3,
      seed: "Galadriel"
    };

    secretMove_p1 = ethers.utils.solidityKeccak256(["uint256","string"],[player1.move, player1.seed]);
    secretMove_p2 = ethers.utils.solidityKeccak256(["uint256","string"],[player2.move, player2.seed]);

    gameId = 0;
  });

  describe("Create game", function () {
    it("Should return owner of created game", async function () {
      await rps.connect(addr1).createGame();

      let gameStruct = await rps.games(0);
      let ownerOfGame = gameStruct.owner;
      expect(ownerOfGame).to.equal(addr1.address);
    });
  });

  describe("Join created game", function () {
    it("Should return challenger of created game", async function () {
      await rps.connect(addr1).createGame();
      await rps.connect(addr2).joinGame(gameId);

      let gameStruct = await rps.games(0);
      let challengerOfGame = gameStruct.challenger;

      expect(challengerOfGame).to.equal(addr2.address);
    });
  });

  describe("Play game", function () {
    it("Should emit win for player1", async function () {
      await rps.connect(addr1).createGame({value: 0});
      await rps.connect(addr2).joinGame(gameId, {value: 0});
      await rps.connect(addr1).submitMove(gameId, secretMove_p1);
      await rps.connect(addr2).submitMove(gameId, secretMove_p2);
      await rps.connect(addr1).revealMove(gameId, player1.move, player1.seed);

      await expect(rps.connect(addr2).revealMove(gameId, player2.move, player2.seed))
        .to.emit(rps, "win")
        .withArgs(addr1.address);
    });

    describe("Withdraw revert", function () {
      it("Should return revert on withdraw function when game is in READY status", async function () {
        await rps.connect(addr1).createGame();
        await rps.connect(addr2).joinGame(gameId);

        await expect(rps.connect(addr1).withdrawBeforeGameStart(gameId))
          .to.be.revertedWith("Game status should be OPEN to perform that action");
      });
    });

    describe("Winner payout", function () {
      it("Should send funds to winner account", async function () {
        await rps.connect(addr1).createGame({value: ethers.utils.parseEther("0.15")});
        await rps.connect(addr2).joinGame(gameId, {value: ethers.utils.parseEther("0.15")});
        await rps.connect(addr1).submitMove(gameId, secretMove_p1);
        await rps.connect(addr2).submitMove(gameId, secretMove_p2);
        await rps.connect(addr1).revealMove(gameId, player1.move, player1.seed);

        await expect(await rps.connect(addr2).revealMove(gameId, player2.move, player2.seed))
          .to.changeEtherBalance(addr1, ethers.utils.parseEther("0.3"));
      });
    });
  });
});
