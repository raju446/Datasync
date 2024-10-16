public class Downstream {
    public static void callUpsertDownstream(Set<Id> recordIds, String objectName) {
        External_ID_Mapping__mdt externalIdMapping = External_ID_Mapping__mdt.getInstance(objectName);
        if (externalIdMapping == null || !externalIdMapping.IsActive__c) {
            // If the mapping is not found or not active, we don't perform any action
            return;
        }

        if (recordIds == null || recordIds.isEmpty() || String.isBlank(objectName)) {
            sendErrorEmail('Invalid parameters for callUpsertDownstream', 
                           'Invalid parameters provided to callUpsertDownstream. Object: ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
            return;
        }

        if (String.isBlank(externalIdMapping.External_ID_Field__c)) {
            sendErrorEmail('External ID field not found', 
                           'External ID field not found for object: ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
            return;
        }

        // Query for records with non-null and non-blank External ID values
        String query = 'SELECT Id FROM ' + objectName + ' WHERE Id IN :recordIds AND ' + externalIdMapping.External_ID_Field__c + ' != null';
        List<SObject> validRecords = Database.query(query);

        Set<Id> validRecordIds = new Set<Id>();
        for (SObject record : validRecords) {
            validRecordIds.add(record.Id);
        }

        if (validRecordIds.isEmpty()) {
            sendErrorEmail('No valid records found', 
                           'No records with valid External ID values found for object: ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
            return;
        }

        if (Limits.getLimitFutureCalls() > Limits.getFutureCalls()) {
            upsertDownstream(validRecordIds, objectName, externalIdMapping.External_ID_Field__c, externalIdMapping.Email_Addresses__c);
        } else {
            sendErrorEmail('Future method limit reached', 
                           'Future method limit reached. Unable to call upsertDownstream for object: ' + objectName,
                           externalIdMapping.Email_Addresses__c.split(','));
        }
    }

    private static void sendErrorEmail(String subject, String body, List<String> toAddresses) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(subject);
        email.setPlainTextBody(body);
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
    }

    @future(callout=true)
    public static void upsertDownstream(Set<Id> recordIds, String objectName, String externalIdField, String toEmails) {
        try {
            Set<String> omitFields = new Set<String>{'IsPartner', 'IsCustomerPortal'};
            
            Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
            Set<String> editableFields = new Set<String>();
            for (Schema.SObjectField fieldRef : fields.values()) {
                Schema.DescribeFieldResult fieldResult = fieldRef.getDescribe();
                if (fieldResult.isUpdateable() && !omitFields.contains(fieldResult.getName())) {
                    editableFields.add(fieldResult.getName());
                }
            }
            
            // Add related object fields to the query
            Set<String> relatedFields = new Set<String>();
            Set<String> fieldsToRemove = new Set<String>();
            for (String field : editableFields) {
                Schema.DescribeFieldResult fieldDescribe = fields.get(field).getDescribe();
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                    String relationshipName = fieldDescribe.getRelationshipName();
                    if (relationshipName != null) {
                        String relatedObjectName = fieldDescribe.getReferenceTo()[0].getDescribe().getName();
                        External_ID_Mapping__mdt relatedExternalIdMapping = External_ID_Mapping__mdt.getInstance(relatedObjectName);
                        if (relatedExternalIdMapping != null && String.isNotBlank(relatedExternalIdMapping.External_ID_Field__c)) {
                            relatedFields.add(relationshipName + '.' + relatedExternalIdMapping.External_ID_Field__c);
                            fieldsToRemove.add(field);
                        }
                    }
                }
            }
            // Remove fields that are being handled as related object fields
            editableFields.removeAll(fieldsToRemove); 

            String allFields = String.join(new List<String>(editableFields), ',');
            if (!relatedFields.isEmpty()) {
                allFields += ',' + String.join(new List<String>(relatedFields), ',');
            }

            String query = 'SELECT ' + allFields + ' FROM ' + objectName + ' WHERE Id IN :recordIds';
            List<SObject> sobjList = Database.query(query);
            
            List<SObject> filteredSobjList = new List<SObject>();
            // Add back the fields that were removed earlier to include them in the filtered object
            editableFields.addAll(fieldsToRemove); 
            for (SObject sobj : sobjList) {    
                SObject filteredSobj = sobj.getSObjectType().newSObject();
                for (String field : editableFields) {
                    if (field != 'Id') {  // Skip the Id field
                        Object fieldValue = sobj.get(field);
                        if (fieldValue != null) {
                            if (!fieldsToRemove.contains(field)) {
                                filteredSobj.put(field, fieldValue);
                            }
                            Schema.SObjectField fieldToken = fields.get(field);
                            Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
                            
                            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                                // For lookup fields, we need to get the external ID of the related record
                                String relationshipName = fieldDescribe.getRelationshipName();
                                if (relationshipName != null) {
                                    String relatedObjectName = fieldDescribe.getReferenceTo()[0].getDescribe().getName();
                                    External_ID_Mapping__mdt relatedExternalIdMapping = External_ID_Mapping__mdt.getInstance(relatedObjectName);
                                    if (relatedExternalIdMapping != null && String.isNotBlank(relatedExternalIdMapping.External_ID_Field__c)) {
                                        // Only get the related SObject if it's part of the External ID mapping
                                        SObject relatedRecord = sobj.getSObject(relationshipName);
                                        if (relatedRecord != null) {
                                            Object externalIdValue = relatedRecord.get(relatedExternalIdMapping.External_ID_Field__c);
                                            if (externalIdValue != null) {
                                                system.debug('externalIdValue-------'+externalIdValue);
                                                system.debug('relationshipName-------'+relationshipName);
                                                SObject relatedSObj = Schema.getGlobalDescribe().get(relatedObjectName).newSObject();
                                                relatedSObj.put(relatedExternalIdMapping.External_ID_Field__c, externalIdValue);
                                                filteredSobj.putSObject(relationshipName, relatedSObj);
                                                system.debug('filteredSobj-------'+filteredSobj);
                                            }
                                        }
                                    }
                                }
                            } else {
                                filteredSobj.put(field, fieldValue);
                            }
                        }
                    }
                }
                filteredSobj.put(externalIdField, sobj.get(externalIdField));
                filteredSobjList.add(filteredSobj);
            }
                        
            JSON2Apex js = new JSON2Apex();
            js.allOrNone = false;
            js.records = filteredSobjList;
            String str = JSON.serialize(js);

            Downstream_Credentials__mdt credentials = Downstream_Credentials__mdt.getInstance('DataSrc2_API_Credentials');
            String username = credentials.Username__c;
            String password = credentials.Password__c;
            String clientId = credentials.Client_Id__c;
            String clientSecret = credentials.Client_Secret__c;
            String secretToken = credentials.Secret_Token__c;
            String instanceUrl = credentials.Endpoint_URL__c;

            String accessToken = getAccessToken(instanceUrl, clientId, clientSecret, username, password, secretToken);
            if (accessToken == null) {
                sendErrorEmail('Failed to get access token', 'Unable to obtain access token', toEmails.split(','));
                return;
            }

            HttpRequest reqNew = new HttpRequest();
            reqNew.setEndpoint(instanceUrl + '/services/data/v61.0/composite/sobjects/' + objectName + '/' + externalIdField);
            reqNew.setMethod('PATCH');
            reqNew.setHeader('Authorization', 'Bearer ' + accessToken);
            reqNew.setHeader('Content-Type', 'application/json');
            reqNew.setBody(str);
            reqNew.setTimeout(120000);

            Http httpNew = new Http();
            HttpResponse resNew = httpNew.send(reqNew);

            handleResponse(resNew, toEmails);

        } catch (Exception e) {
            sendErrorEmail('Failed to upsert records', e.getMessage(), toEmails.split(','));
        }
    }

    private static String getAccessToken(String instanceUrl, String clientId, String clientSecret, String username, String password, String secretToken) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(instanceUrl + '/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=password' +
                    '&client_id=' + clientId +
                    '&client_secret=' + clientSecret +
                    '&username=' + username +
                    '&password=' + password + secretToken);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> authResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) authResponse.get('access_token');
        }
        return null;
    }

    private static void handleResponse(HttpResponse resNew, String toEmails) {
        if (resNew.getStatusCode() == 200) {
            Object parsedResponse = JSON.deserializeUntyped(resNew.getBody());
            Boolean hasError = false;
            String errorMessage = '';

            if (parsedResponse instanceof List<Object>) {
                List<Object> responseList = (List<Object>) parsedResponse;
                for (Object item : responseList) {
                    if (item instanceof Map<String, Object>) {
                        Map<String, Object> itemMap = (Map<String, Object>) item;
                        if (itemMap.containsKey('success') && !(Boolean)itemMap.get('success')) {
                            hasError = true;
                            errorMessage += 'Error in item: ' + JSON.serialize(itemMap) + '\n';
                        }
                    }
                }
            } else if (parsedResponse instanceof Map<String, Object>) {
                Map<String, Object> responseMap = (Map<String, Object>) parsedResponse;
                if (responseMap.containsKey('success') && !(Boolean)responseMap.get('success')) {
                    hasError = true;
                    errorMessage = 'Error in response: ' + JSON.serialize(responseMap);
                }
            }

            if (hasError) {
                sendErrorEmail('Failed to upsert records (Success status false)', errorMessage, toEmails.split(','));
            } else {
                System.debug('Records upserted successfully');
            }
        } else {
            sendErrorEmail('Failed to upsert records', resNew.getBody(), toEmails.split(','));
        }
    }

    public class JSON2Apex {
        public Boolean allOrNone;
        public List<SObject> records;
    }

    public class CustomException extends Exception {}
}