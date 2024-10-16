public class UpsertBatchProcessor implements Database.Batchable<SObject>, Database.Stateful, Database.AllowsCallouts {
    private String query;
    private String objectName;
    private Set<String> toEmails;
    private Set<String> editableFields;
    private Set<String> fieldsToRemove;
    private Id jobMasterId;
    private String jobName;
    private String sourceKeyField;
    private String targetKeyField;

    public UpsertBatchProcessor(String query, String objectName, String toEmails, String jobName, String sourceKeyField, String targetKeyField) {
        try {
            System.debug('objectName--' + objectName);
            External_ID_Mapping__mdt externalIdMapping = External_ID_Mapping__mdt.getInstance(objectName);

            if (externalIdMapping == null || !externalIdMapping.IsActive__c) {
                throw new IllegalArgumentException('Invalid object name or inactive mapping for object: ' + objectName);
            }

            if (String.isBlank(query) || String.isBlank(objectName) || String.isBlank(sourceKeyField) || String.isBlank(targetKeyField)) {
                throw new IllegalArgumentException('Invalid parameters provided to UpsertBatchProcessor. Query: ' + query + ', Object: ' + objectName + ', Source Key Field: ' + sourceKeyField + ', Target Key Field: ' + targetKeyField);
            }

            this.query = query;
            this.objectName = objectName;
            this.jobName = jobName;
            this.sourceKeyField = sourceKeyField;
            this.targetKeyField = targetKeyField;
            this.toEmails = new Set<String>();
            if (String.isNotBlank(toEmails)) {
                this.toEmails.addAll(toEmails.split(','));
            }
            if (String.isNotBlank(externalIdMapping.Email_Addresses__c)) {
                this.toEmails.addAll(externalIdMapping.Email_Addresses__c.split(','));
            }
            this.editableFields = new Set<String>();
            this.fieldsToRemove = new Set<String>();
        } catch (Exception e) {
            sendErrorEmail('Error in UpsertBatchProcessor constructor', e.getMessage() + '\n' + e.getStackTraceString(), new List<String>(this.toEmails));
            throw e;
        }
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        try {
            AsyncApexJob job = [SELECT Id, Status, JobType, TotalJobItems, JobItemsProcessed, NumberOfErrors, CreatedDate
                                FROM AsyncApexJob WHERE Id = :BC.getJobId()];

            Job_Master__c jobMaster = new Job_Master__c(
                Object_Name__c = this.objectName,
                Status__c = job.Status,
                Start_Time__c = job.CreatedDate,
                Total_Records__c = job.TotalJobItems,
                Successful_Records__c = 0,
                Failed_Records__c = 0,
                Name = this.jobName
            );
            insert jobMaster;
            this.jobMasterId = jobMaster.Id;

            Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
            Set<String> queryFields = new Set<String>(query.toLowerCase().substringAfter('select ').substringBefore(' from').split(','));
            editableFields.clear();
            fieldsToRemove.clear();

            for (String field : queryFields) {
                if (fields.containsKey(field.trim().toLowerCase())) { 
                    Schema.DescribeFieldResult fieldResult = fields.get(field.trim()).getDescribe();
                    if (fieldResult.isUpdateable() || field.trim().equalsIgnoreCase('Id')) {
                        editableFields.add(fieldResult.getName());
                    }
                }
            }
            System.debug('editableFields-------' + editableFields);

            String allFields = String.join(new List<String>(editableFields), ',');
            System.debug('allFields-------' + allFields);
            /*if (!relatedFields.isEmpty()) {
                allFields += ',' + String.join(new List<String>(relatedFields), ',');
            }*/

            System.debug('allFields1-------' + allFields);
            String finalQuery = query.replaceFirst('(?i)SELECT\\s+(.*?)\\s+FROM', 'SELECT ' + allFields + ' FROM');
            
            if (!fieldsToRemove.isEmpty()) {
                editableFields.addAll(fieldsToRemove); 
            }
            System.debug('finalQuery-------' + finalQuery);
            return Database.getQueryLocator(finalQuery);
        } catch (Exception e) {
            sendErrorEmail('Error in start method', e.getMessage() + '\n' + e.getStackTraceString(), new List<String>(this.toEmails));
            throw e;
        }
    }

    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        try {
            List<SObject> filteredSobjList = new List<SObject>();
            Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
            
            for (SObject sobj : scope) {    
                SObject filteredSobj = sobj.getSObjectType().newSObject();
                
                for (String field : editableFields) {
                    if (field != 'Id') {
                        Object fieldValue = sobj.get(field);
                        if (fieldValue != null) {
                            if (!fieldsToRemove.contains(field)) {
                                filteredSobj.put(field, fieldValue);
                            }
                        }
                    }
                }
                // Map the source field value to the target field
                filteredSobj.put(targetKeyField, sobj.get(sourceKeyField));
                filteredSobjList.add(filteredSobj);
            }
           system.debug('filteredSobjList-------'+filteredSobjList);             
            JSON2Apex js = new JSON2Apex();
            js.allOrNone = false;
            js.records = filteredSobjList;
            String jsonBody = JSON.serialize(js);

            Downstream_Credentials__mdt credentials = Downstream_Credentials__mdt.getInstance('DataSrc2_API_Credentials');
            String username = credentials.Username__c;
            String password = credentials.Password__c;
            String clientId = credentials.Client_Id__c;
            String clientSecret = credentials.Client_Secret__c;
            String secretToken = credentials.Secret_Token__c;
            String instanceUrl = credentials.Endpoint_URL__c;

            String accessToken = getAccessToken(instanceUrl, clientId, clientSecret, username, password, secretToken);
            if (accessToken == null) {
                sendErrorEmail('Failed to get access token', 'Unable to obtain access token', new List<String>(toEmails));
                return;
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(instanceUrl + '/services/data/v61.0/composite/sobjects/' + objectName + '/' + targetKeyField);
            req.setMethod('PATCH');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            req.setBody(jsonBody);
            req.setTimeout(120000);

            Http http = new Http();
            HttpResponse res = http.send(req);

            Pipeline__c pipelineRecord = new Pipeline__c(
                Job_Master__c = this.jobMasterId,
                Status__c = 'Completed',
                NumberOfErrors__c = 0,
                Records_Processed__c  = scope.size()
            );
            insert pipelineRecord;

            handleResponse(res, new List<String>(toEmails), scope, editableFields, pipelineRecord.Id);
        } catch (Exception e) {
            sendErrorEmail('Error in execute method', e.getMessage() + '\n' + e.getStackTraceString(), new List<String>(toEmails));
        }
    }

    public void finish(Database.BatchableContext BC) {
        System.debug('Batch job finished');
        AsyncApexJob job = [SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems 
                            FROM AsyncApexJob WHERE Id = :BC.getJobId()];
        
        Job_Master__c jobMaster = [SELECT Id, Status__c, Total_Records__c, Successful_Records__c, 
                                   Failed_Records__c, End_Time__c 
                                   FROM Job_Master__c WHERE Id = :jobMasterId];
        
        jobMaster.Status__c = job.Status;
        jobMaster.Total_Records__c = job.TotalJobItems;
        jobMaster.Successful_Records__c = job.JobItemsProcessed - job.NumberOfErrors;
        jobMaster.Failed_Records__c = job.NumberOfErrors;
        jobMaster.End_Time__c = System.now();
        
        update jobMaster;
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

    private static void handleResponse(HttpResponse resNew, List<String> toEmails, List<SObject> scope, Set<String> editableFields, Id pipelineId) {
        List<ErrorRecord> errorRecords = new List<ErrorRecord>();
        if (resNew.getStatusCode() == 200) {
            Object parsedResponse = JSON.deserializeUntyped(resNew.getBody());
            Boolean hasError = false;
            String errorMessage = '';

            if (parsedResponse instanceof List<Object>) {
                List<Object> responseList = (List<Object>) parsedResponse;
                for (Integer i = 0; i < responseList.size(); i++) {
                    Object item = responseList[i];
                    if (item instanceof Map<String, Object>) {
                        Map<String, Object> itemMap = (Map<String, Object>) item;
                        if (itemMap.containsKey('success') && !(Boolean)itemMap.get('success')) {
                            hasError = true;
                            errorMessage += 'Error in item: ' + JSON.serialize(itemMap) + '\n';
                            
                            // Create ErrorRecord
                            ErrorRecord errorRecord = new ErrorRecord();
                            for (String field : editableFields) {
                                errorRecord.fields.put(field, String.valueOf(scope[i].get(field)));
                            }
                            errorRecord.errorMessage = String.valueOf(itemMap.get('errors'));
                            errorRecords.add(errorRecord);
                        }
                    }
                }
            } else if (parsedResponse instanceof Map<String, Object>) {
                Map<String, Object> responseMap = (Map<String, Object>) parsedResponse;
                if (responseMap.containsKey('success') && !(Boolean)responseMap.get('success')) {
                    hasError = true;
                    errorMessage = 'Error in response: ' + JSON.serialize(responseMap);
                    
                    // Create ErrorRecord for single record error
                    ErrorRecord errorRecord = new ErrorRecord();
                    for (String field : editableFields) {
                        errorRecord.fields.put(field, String.valueOf(scope[0].get(field)));
                    }
                    errorRecord.errorMessage = errorMessage;
                    errorRecords.add(errorRecord);
                }
            }

            if (hasError) {
                sendErrorEmail('Failed to upsert records (Success status false)', errorMessage, toEmails);
                createErrorAttachment(errorRecords, pipelineId);
            } else {
                System.debug('Records upserted successfully');
            }
        } else {
            sendErrorEmail('Failed to upsert records', resNew.getBody(), toEmails);
            
            // Create ErrorRecord for HTTP error
            ErrorRecord errorRecord = new ErrorRecord();
            errorRecord.errorMessage = 'HTTP Error: ' + resNew.getStatusCode() + ' ' + resNew.getStatus();
            errorRecords.add(errorRecord);
            createErrorAttachment(errorRecords, pipelineId);
        }
    }

    private static void createErrorAttachment(List<ErrorRecord> errorRecords, Id pipelineId) {
        if (errorRecords.isEmpty()) return;

        String csvContent = 'Error Message';
        for (String field : errorRecords[0].fields.keySet()) {
            csvContent += ',' + field;
        }
        csvContent += '\n';

        for (ErrorRecord record : errorRecords) {
            csvContent += '"' + record.errorMessage.replace('"', '""') + '"';
            for (String field : record.fields.values()) {
                csvContent += ',"' + (field != null ? field.replace('"', '""') : '') + '"';
            }
            csvContent += '\n';
        }

        Attachment attachment = new Attachment();
        attachment.ParentId = pipelineId;
        attachment.Name = 'ErrorRecords_' + System.now().format('yyyyMMdd_HHmmss') + '.csv';
        attachment.Body = Blob.valueOf(csvContent);
        attachment.ContentType = 'text/csv';
        
        insert attachment;
    }

    private static void sendErrorEmail(String subject, String body, List<String> toAddresses) {
        if (toAddresses != null && !toAddresses.isEmpty()) {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(toAddresses);
            email.setSubject(subject);
            email.setPlainTextBody(body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{email});
        } else {
            System.debug('Error: ' + subject + '\n' + body);
        }
    }

    public class JSON2Apex {
        public Boolean allOrNone;
        public List<SObject> records;
    }

    private class ErrorRecord {
        Map<String, String> fields = new Map<String, String>();
        String errorMessage;
    }

    public class CustomException extends Exception {}
}