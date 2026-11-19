/**
 * Agentforce action: Ascend Retail - Verify Shopper.
 * Salesforce allows only one @InvocableMethod per class, so each action is its own class.
 * The rules live in AscendRetailAgent.
 */
public with sharing class AscendRetailVerify {
    @InvocableMethod(
        label='Ascend Retail - Verify Shopper'
        description='Verifies a shopper using their order number plus the email on the order. Returns verified=true only on an exact match.'
    )
    public static List<AscendRetailAgent.VerifyResponse> verifyShopper(List<AscendRetailAgent.VerifyRequest> requests) {
        return AscendRetailAgent.verifyShopper(requests);
    }
}