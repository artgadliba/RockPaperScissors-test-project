// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";

contract RockPaperScissors {
    Using SafeMath for uint256;
    
    enum GameStatus { OPEN, READY, CLOSED, DONE }

    struct Game {
        GameStatus status;
        address owner;
        address challenger;
        uint256 funds;
        uint256 timer;
        mapping (address => bytes32) playerSecretMove;
        mapping (address => uint256) playerRevealedMove;
    }

    Game[] public games;

    mapping (address => uint256) lastWinAmount;

    event gameCreated(uint256 gameId, address owner, uint256 bid);
    event gameJoined(uint256 gameId, address owner, address challenger, uint256 bid);
    event inviteGame(uint256 gameId, address challenger);
    event submitedSecretMove(address player, bytes32 move);
    event moveRevealed(uint256 gameId, address player, uint256 move);
    event draw(address player1, address player2);
    event win(address player);
    event gameClosed(uint256 gameId);

    /// @dev Makes sure player is part of the game
    modifier _onlyPlayer(uint256 gameId) {
        require(msg.sender == games[gameId].owner || msg.sender == games[gameId].challenger, "You should be a player of that game to interract");
        _;
    }

    /// @dev Makes sure player is owner of the game
    modifier _onlyGameOwner(uint256 gameId) {
        require(msg.sender == games[gameId].owner, "You should be the owner of that game to do that");
        _;
    }

    /// @dev Makes sure game.status is OPEN
    modifier _gameOpen(uint256 gameId) {
        require(games[gameId].status == GameStatus.OPEN, "Game status should be OPEN to perform that action");
        _;
    }

    /// @dev Makes sure game.status is READY
    modifier _gameReady(uint256 gameId) {
        require(games[gameId].status == GameStatus.READY, "Game status should be READY to perform that action");
        _;
    }

    /// @dev Makes sure game.status is CLOSED
    modifier _gameClosed(uint256 gameId) {
        require(games[gameId].status == GameStatus.CLOSED, "Game status should be CLOSED to perform that action");
        _;
    }

    /// @dev Makes sure both players in one game submitted their moves
    modifier bothMovesSubmited(uint256 gameId) {
        address p1 = games[gameId].owner;
        address p2 = games[gameId].challenger;
        require(games[gameId].playerSecretMove[p1] != 0 && games[gameId].playerSecretMove[p2] != 0,
            "Both players should submit their move to perform that action");
        _;
    }

    // @dev Function for any player to create new game.
    function createGame() public payable {
        uint256 gameId = games.length;
        games.push();

        Game storage g = games[gameId];
        g.status = GameStatus.OPEN;
        g.owner = msg.sender;
        g.funds = msg.value;

        emit gameCreated(gameId, msg.sender, msg.value);
  }
    // @dev Function to any player to join created game
    function joinGame(uint256 gameId) public payable _gameOpen(gameId) {
        require(games[gameId].owner != msg.sender, "You cannnot join game created by yourself");
        require(games[gameId].funds == msg.value, "You should bet the same value as game owner");
        require(games[gameId].challenger == address(0) || games[gameId].challenger == msg.sender, "You cannot join game offered to someone else");

        if (games[gameId].challenger == address(0)) {
             games[gameId].challenger = msg.sender;
        }

        games[gameId].status = GameStatus.READY;
        games[gameId].funds += msg.value;
        games[gameId].timer = block.timestamp;

        emit gameJoined(gameId, games[gameId].owner, msg.sender, msg.value);

    }

    // @dev Function to game owner to invite
    function inviteToGame(uint256 gameId, address challenger) external _onlyGameOwner(gameId) {
        games[gameId].challenger = challenger;

        emit inviteGame(gameId, challenger);
    }

    // @dev Function for invited player to join game
    function acceptInvitation(uint256 gameId) external payable {
        require(msg.sender == games[gameId].challenger);
        joinGame(gameId);
    }

    // @dev Internal function to get players opponent address
    function getOpponent(uint256 gameId, address player) private view returns(address) {
        return games[gameId].owner == player ? games[gameId].challenger : games[gameId].owner;
    }

    // @dev To submit move you need to choose one of the following actions: 1.Rock 2.Paper 3.Scissors by enter according number
    // @param secretMove - hashed value of move and seed phrase genereated off-chain (provides fair play)
    function submitMove(uint256 gameId, bytes32 secretMove) external _gameReady(gameId) {
        require(games[gameId].playerSecretMove[msg.sender] == 0, "You cannot change your move");

        games[gameId].playerSecretMove[msg.sender] = secretMove;
        games[gameId].timer = block.timestamp; // Set new value to timer then move submited to provide extra time

        emit submitedSecretMove(msg.sender, secretMove);
    }

    // @dev Function to make play, compares moves and provides result
    function compareMoves(uint256 gameId) private {
        address payable player1 = payable(games[gameId].owner);
        address payable player2 = payable(games[gameId].challenger);

        uint256 player1Move = games[gameId].playerRevealedMove[player1];
        uint256 player2Move = games[gameId].playerRevealedMove[player2];

        if (player1Move == player2Move) {
            // Clear all move types for each player in case of draw game
            player1Move = 0;
            player2Move = 0;
            games[gameId].playerSecretMove[player1] = 0;
            games[gameId].playerSecretMove[player2] = 0;

            emit draw(player1, player2); // In case of draw play, players will be noticed by UI and should submit new moves

        } else if (player1Move == 1 && player2Move == 3 ||
            player1Move == 2 && player2Move == 1 ||
            player1Move == 3 && player2Move == 2) {

            games[gameId].status = GameStatus.DONE;
            player1.transfer(games[gameId].funds);
            lastWinAmount[player1] = games[gameId].funds;

            emit win(player1);

        } else {

            games[gameId].status = GameStatus.DONE;
            player2.transfer(games[gameId].funds);
            lastWinAmount[player2] = games[gameId].funds;

            emit win(player2);
        }
    }

    // @dev Function to reveal players secret moves. Can be used only then both players moves submitted
    // @param move - players move, used previously to generate hashed secret move (should match last submitted move in game)
    // @param seed - players seed phrase, used previously to generate hashed secret move (should match seed phrase used to submit last move in game)
    function revealMove(uint256 gameId, uint256 move, string memory seed) external bothMovesSubmited(gameId) _onlyPlayer(gameId) {
        bytes32 secretMove = getSecret(move, seed);
        address opponent = getOpponent(gameId, msg.sender);

        require(secretMove == games[gameId].playerSecretMove[msg.sender], "You are trying to reveal wrong secret move");
        games[gameId].playerRevealedMove[msg.sender] = move;
        games[gameId].timer = block.timestamp; // Set new value to timer then move revealed to provide extra time

        emit moveRevealed(gameId, msg.sender, move);

        if (games[gameId].playerRevealedMove[msg.sender] != 0
            && games[gameId].playerRevealedMove[opponent] != 0) { // Both players revealed moves are submited

            compareMoves(gameId);
        }
    }
    // @dev Function for any player to bet last winned funds if any
    function betLastWin() external payable {
        require(lastWinAmount[msg.sender] != 0, "You should have previous wins to bet it");
        require(lastWinAmount[msg.sender] == msg.value, "Sending incorrect amount of ether");

        createGame();
    }

    // @dev Function to owner of game to withdraw his bet before other any other player joined
    function withdrawBeforeGameStart(uint256 gameId) external _gameOpen(gameId) _onlyGameOwner(gameId) {
        uint256 amount = games[gameId].funds;
        payable(msg.sender).transfer(amount);

        games[gameId].funds = 0; // Clear game funds store after sending transfer
        games[gameId].status = GameStatus.DONE;
    }

    // @dev Function to both players of specific game to withdraw their bets in case of uncooperative opponent
    function withdrawWhenGameStuck(uint256 gameId) external _gameReady(gameId) _onlyPlayer(gameId) {
        require(games[gameId].timer + 20 minutes <= block.timestamp, "You cannot withdraw before time is out");

        uint256 amount = games[gameId].funds / 2;
        payable(msg.sender).transfer(amount);
        games[gameId].funds = 0; // Clear game funds store after sending transfers
        games[gameId].status = GameStatus.CLOSED;

        emit gameClosed(gameId);
    }

    // @dev Function to reproduce secret move hash
    function getSecret(uint256 move, string memory seed) private pure returns(bytes32) {
        return keccak256(abi.encodePacked(move, seed));
    }
}
