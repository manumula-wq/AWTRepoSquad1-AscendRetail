/**
 * Agentforce action: Ascend Retail - Create Return Request.
 * Salesforce allows only one @InvocableMethod per class, so each action is its own class.
 */
public with sharing class AscendRetailReturn {
    @InvocableMethod(
        label='Ascend Retail - Create Return Request'
        description='Creates a return request Case for ONE eligible shipment. Idempotent. Never issues or promises a refund.'
    )
    public static List<AscendRetailAgent.ReturnResponse> createReturnRequest(List<AscendRetailAgent.ReturnRequest> requests) {
        return AscendRetailAgent.createReturnRequest(requests);
    }
}