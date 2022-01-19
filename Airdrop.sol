// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
//TODO Testear que funciona el porcentaje del 66,66
// Imports
/* import "./Libraries.sol"; */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}
interface IERC20 {
    function decimals() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract FirstPresale is ReentrancyGuard {
    address payable public owner; // Dueño del contrato.
    IERC20 public token; // CRW Token.
    bool private tokenAvailable = false;
    uint public tokensPerBNB = 800000; // Cantidad de CRWs que se van a repartir por cada BNB aportado.
    uint public ending; // Tiempo que va finalizar la preventa.
    bool public presaleStarted = false; // Indica si la preventa ha sido iniciada o no.
    address public deadWallet = 0x000000000000000000000000000000000000dEaD; // Wallet de quemado.
    uint public firstCooldownTime = 2 minutes; //7 days
    uint public cooldownTime = 2 minutes; //3 days
    uint public firstClaimReady;
    uint public tokensSold;
    uint public tokensStillAvailable;
    uint private _firstPresaleTokens = 0.1 * 10**6 * 10**18;

    mapping(address => bool) public whitelist; // Whitelist de inversores permitidos en la preventa.
    mapping(address => uint) public invested; // Cantidad de BNBs que ha invertido cada inversor en la preventa.
    mapping(address => uint) public investorBalance;
    mapping(address => uint) public withdrawableBalance;
    mapping(address => uint) public claimReady;

    constructor(address payable _teamWallet) {
        owner = _teamWallet;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 'You must be the owner.');
        _;
    }

    /**
     * @notice Función que actualiza el token en el contrato (Solo se puede hacer 1 vez).
     * @param _token Dirección del contrato del token.
     */
    function setToken(IERC20 _token) public onlyOwner {
        require(!tokenAvailable, "Token is already inserted.");
        token = _token;
        tokenAvailable = true;
    }

    /**
     * @notice Función que permite añadir inversores a la whitelist.
     * @param _investor Direcciones de los inversores que entran en la whitelist.
     */
    function addToWhitelist(address[] memory _investor) external onlyOwner {
        for (uint _i = 0; _i < _investor.length; _i++) {
            require(_investor[_i] != address(0), 'Invalid address.');
            address _investorAddress = _investor[_i];
            whitelist[_investorAddress] = true;
        }
    }

    /**
     * @notice Función que inicia la Preventa (Solo se puede iniciar una vez).
     * @param _presaleTime Tiempo que va a durar la preventa.
     */
    function startPresale(uint _presaleTime) external onlyOwner {
        require(!presaleStarted, "Presale already started.");

        ending = block.timestamp + _presaleTime;
        firstClaimReady = block.timestamp + firstCooldownTime;
        presaleStarted = true;
    }

    /**
     * @notice Función que te permite comprar CRWs. 
     */
     //TODO FALTA PONER EL LIMITE SUPERIOR CUANDO SE TERMINEN LOS TOKENS
    function invest() public payable nonReentrant {
        require(whitelist[msg.sender], "You must be on the whitelist.");
        require(presaleStarted, "Presale must have started.");
        require(block.timestamp <= ending, "Presale finished.");
        invested[msg.sender] += msg.value; // Actualiza la inversión del inversor.
        require(invested[msg.sender] >= 0.10 ether, "Your investment should be more than 0.10 BNB.");
        require(invested[msg.sender] <= 10 ether, "Your investment cannot exceed 10 BNB.");

        uint _investorTokens = msg.value * tokensPerBNB; // Tokens que va a recibir el inversor.
        tokensStillAvailable += _investorTokens;
        require(tokensStillAvailable <= _firstPresaleTokens, "There are not that much tokens left");
        investorBalance[msg.sender] += _investorTokens;
        withdrawableBalance[msg.sender] += _investorTokens;
        tokensSold += _investorTokens;
    }

    /**
     * @notice Calcula el % de un número.
     * @param x Número.
     * @param y % del número.
     * @param scale División.
     */
    function mulScale (uint x, uint y, uint128 scale) internal pure returns (uint) {
        uint a = x / scale;
        uint b = x % scale;
        uint c = y / scale;
        uint d = y % scale;

        return a * c * scale + a * d + b * c + b * d / scale;
    }

    /**
     * @notice Función que permite a los inversores hacer claim de sus tokens disponibles.
     */
    function claimTokens() external nonReentrant {
        require(whitelist[msg.sender], "You must be on the whitelist.");
        require(block.timestamp > ending, "Presale must have finished.");
        require(firstClaimReady <= block.timestamp, "You can't claim yet.");
        require(claimReady[msg.sender] <= block.timestamp, "You can't claim now.");
        // TODO no llegan los tokens al contrato
        uint _contractBalance = token.balanceOf(address(this));
        require(_contractBalance > 0, "Insufficient contract balance.");
        require(investorBalance[msg.sender] > 0, "Insufficient investor balance.");

        uint _withdrawableTokensBalance = mulScale(investorBalance[msg.sender], 5000, 10000); // 5000 basis points = 50%.

        // Si tu balance es menor a la cantidad que puedes retirar directamente te transfiere todo tu saldo.
        if(withdrawableBalance[msg.sender] <= _withdrawableTokensBalance) {
            token.transfer(msg.sender, withdrawableBalance[msg.sender]);

            investorBalance[msg.sender] = 0;
            withdrawableBalance[msg.sender] = 0;
        } else {
            claimReady[msg.sender] = block.timestamp + cooldownTime; // Actualiza cuando será el próximo claim.

            withdrawableBalance[msg.sender] -= _withdrawableTokensBalance; // Actualiza el balance del inversor.

            token.transfer(msg.sender, _withdrawableTokensBalance); // Transfiere los tokens.
        }
    }

    /**
     * @notice Función que permite retirar los BNBs del contrato a la dirección del owner.
     */
    function withdrawBnbs() external onlyOwner {
        uint _bnbBalance = address(this).balance;
        payable(owner).transfer(_bnbBalance);
    }
    
    function finishPresaleBurnOrBack() external onlyOwner {
        require(block.timestamp > ending, "Presale must have finished.");
        
        // If 66% of tokens aren't sold, it will send back to owner address
        uint minTokensSold = _firstPresaleTokens * 2 / 3;
        /* uint _contractBalance = token.balanceOf(address(this)); */
        uint _tokenBalance = _firstPresaleTokens - tokensSold;
        if(_tokenBalance >= minTokensSold){
            _backTokens(_tokenBalance);
        }else{
            _burnTokens(_tokenBalance);
        }
    }

    /**
     * @notice Función que quema los tokens que sobran en la preventa.
     */
    function _burnTokens(uint _tokenBalance) private {
        token.transfer(deadWallet, _tokenBalance);
    }
    
    function _backTokens(uint _tokenBalance) private {
        token.transfer(owner, _tokenBalance);
    }
}