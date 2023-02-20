- buyCart function has got [_sellers], [_cartPrice], [_payload], [deadline] and [_signature].
When user puts several NFT items to the cart , those infos will be stored in backend db.
In backend-side, we will calculate cart-total price from individual item listing price and
send cart-total price as [_cartPrice] paramter of buyCart.
[_cartPrice] will be calculated from backend listing db , confirmed and signed so 
there can be no discrepancy between cart price and sum of individual selling item price.

- in the first line of buyCart, total CartPrice will be transferred from buyer to contract address.
So there won't be any case - sufficient voxel on the contract to pay the sellers.
If buyer doesn't have enough vxl token for cart price , the transaction will be failed from first line.

Marketplace is rely-on backend process and our backend  & dbs are very stable and  safe.
This is our model.
