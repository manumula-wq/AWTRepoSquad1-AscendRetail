/**
 * AWT Workshop 2 - Squad 1 / V1 Retail (Ascend Retail).
 *
 * Agentforce actions for the "returns" agent. The three invocable actions
 * (one @InvocableMethod per class, which Salesforce requires) are
 * AscendRetailVerify, AscendRetailShipments, and AscendRetailReturn.
 * They delegate here:
 *
 *   1. verifyShopper        - verify the shopper (order number + email on the order)
 *   2. getShipments         - look up shipments for an order and explain return eligibility
 *   3. createReturnRequest  - take the one transactional action: log a return request Case
 *
 * Business rules enforced here (defence in depth - the topic instructions also
 * enforce them, but the action is the last line of defence):
 *   - Returns allowed only within 30 days of delivery.
 *   - Final-sale items cannot be returned.
 *   - Only one return request per shipment (idempotent).
 *   - The action NEVER issues or promises a refund.
 */
public with sharing class AscendRetailAgent {

    private static final Integer RETURN_WINDOW_DAYS = 30;
    private static final String RETURN_CASE_TYPE = 'Return';

    // ---------------------------------------------------------------------
    // Action 1: Verify shopper
    // ---------------------------------------------------------------------
    public class VerifyRequest {
        @InvocableVariable(label='Order Number' required=true)
        public String orderNumber;
        @InvocableVariable(label='Email on the order' required=true)
        public String email;
    }

    public class VerifyResponse {
        @InvocableVariable(label='Verified')
        public Boolean verified;
        @InvocableVariable(label='Contact Id')
        public String contactId;
        @InvocableVariable(label='Shopper Name')
        public String shopperName;
        @InvocableVariable(label='Message')
        public String message;
    }

    public static List<VerifyResponse> verifyShopper(List<VerifyRequest> requests) {
        List<VerifyResponse> responses = new List<VerifyResponse>();
        for (VerifyRequest req : requests) {
            VerifyResponse res = new VerifyResponse();
            res.verified = false;

            String orderNumber = req.orderNumber == null ? '' : req.orderNumber.trim();
            String email = req.email == null ? '' : req.email.trim();

            if (String.isBlank(orderNumber) || String.isBlank(email)) {
                res.message = 'Both an order number and the email on the order are required to verify you.';
                responses.add(res);
                continue;
            }

            List<Shop_Order__c> orders = [
                SELECT Id, Order_Number__c, Contact__c, Contact__r.Name, Contact__r.Email
                FROM Shop_Order__c
                WHERE Order_Number__c = :orderNumber
                LIMIT 50
            ];

            Boolean matched = false;
            for (Shop_Order__c o : orders) {
                if (o.Contact__r != null && o.Contact__r.Email != null
                        && o.Contact__r.Email.equalsIgnoreCase(email)) {
                    res.verified = true;
                    res.contactId = o.Contact__c;
                    res.shopperName = o.Contact__r.Name;
                    matched = true;
                    break;
                }
            }

            res.message = matched
                ? 'Verified. Thanks - I can help with this order.'
                : 'I could not verify you with that order number and email. I can only continue once you are verified.';
            responses.add(res);
        }
        return responses;
    }

    // ---------------------------------------------------------------------
    // Action 2: Look up shipments + eligibility
    // ---------------------------------------------------------------------
    public class ShipmentsRequest {
        @InvocableVariable(label='Order Number' required=true)
        public String orderNumber;
        @InvocableVariable(label='Verified Contact Id' required=true description='Contact Id returned by the verify action. Lookups are refused without it.')
        public String verifiedContactId;
    }

    public class ShipmentsResponse {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Shipments')
        public List<ShipmentInfo> shipments;
    }

    public class ShipmentInfo {
        @InvocableVariable(label='Shop Order Id')
        public String shopOrderId;
        @InvocableVariable(label='Shipment Name')
        public String shipmentName;
        @InvocableVariable(label='Item')
        public String item;
        @InvocableVariable(label='Status')
        public String status;
        @InvocableVariable(label='Delivered Date')
        public Date deliveredDate;
        @InvocableVariable(label='Final Sale')
        public Boolean finalSale;
        @InvocableVariable(label='Return Eligible')
        public Boolean returnEligible;
        @InvocableVariable(label='Eligibility Reason')
        public String eligibilityReason;
        @InvocableVariable(label='Has Existing Return')
        public Boolean hasExistingReturn;
    }

    public static List<ShipmentsResponse> getShipments(List<ShipmentsRequest> requests) {
        List<ShipmentsResponse> responses = new List<ShipmentsResponse>();
        for (ShipmentsRequest req : requests) {
            ShipmentsResponse res = new ShipmentsResponse();
            res.shipments = new List<ShipmentInfo>();

            String orderNumber = req.orderNumber == null ? '' : req.orderNumber.trim();
            if (String.isBlank(orderNumber) || String.isBlank(req.verifiedContactId)) {
                res.success = false;
                res.message = 'I need a verified shopper and an order number before I can look anything up.';
                responses.add(res);
                continue;
            }

            // Only return shipments that belong to the verified contact - never another person's data.
            List<Shop_Order__c> orders = [
                SELECT Id, Name, Item__c, Status__c, Delivered_Date__c, Final_Sale__c,
                       Policy_Return_Eligible__c, Return_Eligibility_Reason__c, Contact__c
                FROM Shop_Order__c
                WHERE Order_Number__c = :orderNumber
                  AND Contact__c = :req.verifiedContactId
                ORDER BY Item__c
            ];

            if (orders.isEmpty()) {
                res.success = false;
                res.message = 'I could not find any shipments on that order for your account.';
                responses.add(res);
                continue;
            }

            Set<Id> orderIds = new Map<Id, Shop_Order__c>(orders).keySet();
            Set<Id> withReturns = shipmentsWithExistingReturn(orderIds);

            for (Shop_Order__c o : orders) {
                ShipmentInfo info = new ShipmentInfo();
                info.shopOrderId = o.Id;
                info.shipmentName = o.Name;
                info.item = o.Item__c;
                info.status = o.Status__c;
                info.deliveredDate = o.Delivered_Date__c;
                info.finalSale = o.Final_Sale__c;
                info.returnEligible = o.Policy_Return_Eligible__c && !withReturns.contains(o.Id);
                info.hasExistingReturn = withReturns.contains(o.Id);
                info.eligibilityReason = withReturns.contains(o.Id)
                    ? 'A return request already exists for this shipment.'
                    : o.Return_Eligibility_Reason__c;
                res.shipments.add(info);
            }

            res.success = true;
            res.message = 'Found ' + res.shipments.size() + ' shipment(s) on order ' + orderNumber + '.';
            responses.add(res);
        }
        return responses;
    }

    // ---------------------------------------------------------------------
    // Action 3: Create return request (the one transactional action)
    // ---------------------------------------------------------------------
    public class ReturnRequest {
        @InvocableVariable(label='Shop Order Id' required=true description='Id of the specific shipment to return.')
        public String shopOrderId;
        @InvocableVariable(label='Verified Contact Id' required=true)
        public String verifiedContactId;
    }

    public class ReturnResponse {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        @InvocableVariable(label='Message')
        public String message;
    }

    public static List<ReturnResponse> createReturnRequest(List<ReturnRequest> requests) {
        List<ReturnResponse> responses = new List<ReturnResponse>();
        for (ReturnRequest req : requests) {
            ReturnResponse res = new ReturnResponse();
            res.success = false;

            if (String.isBlank(req.shopOrderId) || String.isBlank(req.verifiedContactId)) {
                res.message = 'I need a verified shopper and the specific shipment before I can log a return.';
                responses.add(res);
                continue;
            }

            Id shopOrderId;
            Id contactId;
            try {
                shopOrderId = (Id) req.shopOrderId;
                contactId = (Id) req.verifiedContactId;
            } catch (Exception e) {
                res.message = 'That shipment reference is not valid.';
                responses.add(res);
                continue;
            }

            List<Shop_Order__c> orders = [
                SELECT Id, Name, Item__c, Delivered_Date__c, Final_Sale__c,
                       Policy_Return_Eligible__c, Return_Eligibility_Reason__c, Contact__c
                FROM Shop_Order__c
                WHERE Id = :shopOrderId
                LIMIT 1
            ];
            if (orders.isEmpty()) {
                res.message = 'I could not find that shipment.';
                responses.add(res);
                continue;
            }
            Shop_Order__c o = orders[0];

            // Guardrail: the shipment must belong to the verified shopper.
            if (o.Contact__c != contactId) {
                res.message = 'That shipment is not on your account, so I cannot log a return for it.';
                responses.add(res);
                continue;
            }

            // Business rule: policy eligibility (window + final sale).
            if (!o.Policy_Return_Eligible__c) {
                res.message = o.Return_Eligibility_Reason__c
                    + ' I cannot create a return for this shipment.';
                responses.add(res);
                continue;
            }

            // Business rule: only one return request per shipment (idempotent).
            List<Case> existing = [
                SELECT Id, CaseNumber
                FROM Case
                WHERE Shop_Order__c = :shopOrderId AND Type = :RETURN_CASE_TYPE
                ORDER BY CreatedDate
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                res.success = true;
                res.caseNumber = existing[0].CaseNumber;
                res.message = 'A return request already exists for this shipment (Case '
                    + existing[0].CaseNumber + '). No new request was created, and no refund is issued or promised.';
                responses.add(res);
                continue;
            }

            Case c = new Case(
                Type = RETURN_CASE_TYPE,
                Status = 'New',
                Origin = 'Agent',
                Subject = 'Return request - ' + o.Item__c + ' (' + o.Name + ')',
                Description = 'Return requested via Ascend Retail agent for shipment ' + o.Name
                    + ' (' + o.Item__c + '). Policy-eligible within the 30-day window; not a final-sale item.',
                ContactId = contactId,
                Shop_Order__c = shopOrderId
            );
            insert c;

            Case inserted = [SELECT CaseNumber FROM Case WHERE Id = :c.Id LIMIT 1];
            res.success = true;
            res.caseNumber = inserted.CaseNumber;
            res.message = 'Your return request for ' + o.Item__c + ' is logged (Case '
                + inserted.CaseNumber + '). No refund is issued or promised - a team member will follow up.';
            responses.add(res);
        }
        return responses;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------
    private static Set<Id> shipmentsWithExistingReturn(Set<Id> shopOrderIds) {
        Set<Id> result = new Set<Id>();
        for (Case c : [
            SELECT Shop_Order__c
            FROM Case
            WHERE Shop_Order__c IN :shopOrderIds AND Type = :RETURN_CASE_TYPE
        ]) {
            result.add(c.Shop_Order__c);
        }
        return result;
    }
}