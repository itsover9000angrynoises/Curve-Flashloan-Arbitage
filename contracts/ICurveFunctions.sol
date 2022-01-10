pragma solidity 0.6.12;

interface ICurveFunctions{
function exchange(
  address pool,
  address from,
  address to,
  uint256 dx,
  uint256 minreturn
  ) external
  returns(uint256);

}