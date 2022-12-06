pragma solidity >= 0.7.0 < 0.9.0;

contract Ownable {// 관리자 권한
    address owner;
    constructor() public {owner = msg.sender;}
    modifier Owned {require(msg.sender == owner); _;} //관리자 권한인지 확인하는 modifier
}

contract BikeData is Ownable {
    //등록된 자전거의 이름을 저장하는 리스트(맵핑은 length를 통해 for문을 돌릴 수 없기 때문에)
    string[] private BikeNameArray;

    //자전거의 정보 : 가격, 이미지, 판매자의 주소를 저장
    struct BikeStruct {
        uint256 BikePrice;
        bytes BikeImage;
        address BikeSeller;
    }

    //자전거의 이름과 정보를 맵핑
    mapping(string => BikeStruct) private BikeInfo;

    //자전거 구매 시간(이름:시간)
    mapping(string => uint256) private purchasedTime;
    //자전거 구매자 정보(
    mapping(string => address) private BikeBuyer;

    //자전거 이름과 가격 출력을 위한 이벤트(일단 이름, 가격, 이미지 소스, 판매자 이름 출력)
    event ShowBikeInfo(string name_of_bike, uint256 price_of_bike, bytes source_of_image, address name_of_seller);
    
    //event ShowBikeInfo(string name_of_bike, BikeStruct _bikeInfo);
    /*
    modifier onlyBefore(uint _time) {
        require(block.timestamp < _time, "Function called too late.");
        _;
    }
    */

    //구매확정기한 지났는지 체크
    function ifTooLate(uint _time) private view returns(bool){
        if(block.timestamp >= _time)
            return true;
        return false;
    }

    receive() external payable {}
    
    //이름으로 자전거 탐색
    function searchBike(string memory _BikeName) public view returns(uint) {
        for(uint256 i = 0; i < BikeNameArray.length; i++)
            if(keccak256(bytes(BikeNameArray[i])) == keccak256(bytes(_BikeName)))
                return i;
        return 999;
    }

    //새 자전거 추가
    function addNewBike(string memory _BikeName, uint256 _price/*, bytes memory _image*/) public payable {
        bytes memory _image;
        require(searchBike(_BikeName) == 999, "The name is duplicated");
        require(_price / 100 <= msg.value, "Check the fee");

        BikeNameArray.push(_BikeName);
        (bool success,) = address(this).call{value: msg.value}("");
        require(success,"Failed to pay");

        //수수료도 너무 많이 보냈을 시 잔액 반환.
        if(_price / 100 < msg.value){
            (bool _success,) = msg.sender.call{value:msg.value - _price / 100}("");
            require(_success,"Failed to return change");
        }

        //구조체..
        BikeInfo[_BikeName] = BikeStruct(_price, _image, msg.sender);

        //BikeFee[_BikeName] = msg.value;
    }

    //자전거 삭제(자전거 구매 확정 시 사용 할 예정)
    function delBike(string memory _BikeName) public Owned {
        require(searchBike(_BikeName) < 999, "Check the name");

        //자전거 등록할 때 지불한 수수료 환불
        (bool _success,) = address(BikeInfo[_BikeName].BikeSeller).call{value: BikeInfo[_BikeName].BikePrice / 100}("");
        require(_success,"Failed to refund fee");

        BikeNameArray[searchBike(_BikeName)] = BikeNameArray[BikeNameArray.length - 1];
        BikeNameArray.pop();

        delete BikeInfo[_BikeName];
    }

    //자전거 구매
    function buyBike(string memory _BikeName) public payable {
        require(searchBike(_BikeName) < 999, "Check the name");
        require(getBikePrice(_BikeName) <= msg.value, "Check the price");

        uint creationTime = block.timestamp;

        BikeBuyer[_BikeName] = msg.sender;
        purchasedTime[_BikeName] = creationTime;
 
        BikeNameArray[searchBike(_BikeName)] = BikeNameArray[BikeNameArray.length - 1];
        BikeNameArray.pop();

        (bool _success,) = address(this).call{value:msg.value}("");
        require(_success,"Failed to pay");

        //보낸 돈이 너무 많으면 잔액 반송.
        if(getBikePrice(_BikeName) < msg.value){
            (bool success,) = msg.sender.call{value:msg.value - getBikePrice(_BikeName)}("");
            require(success,"Failed to return change");
        }
    }

    //구매 확정
    function confirmOrRefundPurchase(string memory _BikeName) public payable {
        //해당 자전거가 구매 내역에 있긴 한지
        require(BikeBuyer[_BikeName] == msg.sender, "This account hasn't purchased the product");
        if (!ifTooLate(purchasedTime[_BikeName] + 60 seconds)) {//만약 3일이 안지났다면 구매 프로세스 진행(임시로 60초 정도로 설정)
            (bool success,) = address(BikeInfo[_BikeName].BikeSeller).call{value: BikeInfo[_BikeName].BikePrice}("");
            (bool _success,) = address(owner).call{value: BikeInfo[_BikeName].BikePrice / 100}("");
            require(success,"Failed to pay");
            require(_success,"Failed to pay");

            delete BikeInfo[_BikeName];
            delete BikeBuyer[_BikeName];
            delete purchasedTime[_BikeName];
        }
        else { //3일 지났으면 그냥 돈 돌려주기. 다만 구매자 확인을 거쳐야 함.
            refund(_BikeName);
            BikeNameArray.push(_BikeName);
            //구매자 명단도 삭제제
            delete BikeBuyer[_BikeName];
            delete purchasedTime[_BikeName];
        }    
    }
    
    //환불
    function refund(string memory _BikeName) private {
        require(BikeBuyer[_BikeName] == msg.sender, "This account hasn't purchased the product");
        (bool _success,) = msg.sender.call{value: BikeInfo[_BikeName].BikePrice}("");
        require(_success, "Failed to pay");
    }

    //자전거 이름으로 검색했을 때 가격 출력
    function getBikePrice(string memory _BikeName) public view returns(uint256) {
        return BikeInfo[_BikeName].BikePrice;
    }

    //등록된 모든 자전거 정보 출력
    function showBike() public {
        for(uint256 i = 0; i <BikeNameArray.length ; i++) {
            string memory _bikeName = BikeNameArray[i];
            //emit ShowBikeInfo(_bikeName, BikeInfo[_bikeName]);
            emit ShowBikeInfo(_bikeName, BikeInfo[_bikeName].BikePrice, BikeInfo[_bikeName].BikeImage, BikeInfo[_bikeName].BikeSeller);
        }
    }

    function showBalance() public view Owned returns(uint256) {
        return address(this).balance;
    }

    function zzz_contractKiller() public Owned {
        selfdestruct(payable(address(this)));
    }
}