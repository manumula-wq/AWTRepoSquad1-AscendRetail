/**
 * Agentforce action: Ascend Retail - Get Shipments.
 * Salesforce allows only one @InvocableMethod per class, so each action is its own class.
 */
public with sharing class AscendRetailShipments {
    @InvocableMethod(
        label='Ascend Retail - Get Shipments'
        description='Returns the shipments for a verified shopper order, each with a plain-language return-eligibility reason. Refuses if the order is not owned by the verified contact.'
    )
    public static List<AscendRetailAgent.ShipmentsResponse> getShipments(List<AscendRetailAgent.ShipmentsRequest> requests) {
        return AscendRetailAgent.getShipments(requests);
    }
}