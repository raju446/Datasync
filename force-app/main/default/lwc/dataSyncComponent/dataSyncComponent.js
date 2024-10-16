import {LightningElement, track , wire, api} from 'lwc';
import getObjects from '@salesforce/apex/DataSyncController.getObjects';
import getFields from '@salesforce/apex/DataSyncController.getFields';
import executeQuery from '@salesforce/apex/DataSyncController.executeQuery';
import getSandboxes from '@salesforce/apex/DataSyncController.getSandboxes';
import initiateOnDemandSync from '@salesforce/apex/DataSyncController.initiateOnDemandSync';
import scheduleWeeklySync from '@salesforce/apex/DataSyncController.scheduleWeeklySync';
import validateSync from '@salesforce/apex/DataSyncController.validateSync';
import getExternalIdFields from '@salesforce/apex/DataSyncController.getExternalIdFields';
import createQueryRecord from '@salesforce/apex/QueryRecordController.createQueryRecord';
import getQueryBanks from '@salesforce/apex/QueryRecordController.getQueryBanks';
import updateRecords from '@salesforce/apex/QueryRecordController.updateRecords';
import deleteRecords from '@salesforce/apex/QueryRecordController.deleteRecords';
import startBulkDataLoaderJob from '@salesforce/apex/QueryRecordController.startBulkDataLoaderJob';
import checkBulkJobStatus from '@salesforce/apex/QueryRecordController.checkBulkJobStatus';
import {refreshApex} from '@salesforce/apex';
import { RefreshEvent } from 'lightning/refresh';
import {ShowToastEvent} from 'lightning/platformShowToastEvent';
import {NavigationMixin} from 'lightning/navigation';

export default class DataSyncComponent extends NavigationMixin(LightningElement) {
   @track objects = [];
   @track selectedObject;
   @track query = '';
   @track queryResults = [];
   @track columns = [];
   @track fields = [];
   @track visibleFields = [];
   @track sourceField;
   @track targetField;
   @track externalIdFields = [];
   @track tragerextIdFields = [];
   @track savedQueryrecordId;
   @track showMoreButton = false;
   @track toastshow = false;
   @track queryBanks;
   @track showqueryBanks = false;
   @track itemsToShow = 10;
   @track isLoading = false;
   @track isQueryLoading = false;
   @track showSavedQueries = false;
   @track isSchduleLoading = false;
   @track isFieldsLoading = false;
   @track isDeleteButtonDisabled = true;
   @track showfields = false;
   @track isdisable = true;
   @track credentialsoptions = [];
   @track draftValues = [];
   @track selectedCredential;
   @track selectedcredentialsValue = '';
   @track isvisible = false;
   @api isModalVisible = false;
   @track isexecute = true;
   @track isorgselection = false;
   @track frequencyvalue;
   @track everyweekvalue = [];
   @track monthofdayvalue = [];
   @track selectedRows;
   @track selectedRowId;
   //@track scheduleJob = false;
   //@track cronJob = false;
   @track isweekly = false;
   @track ismonthly = false;
   @track showStopdate = false;
   @track showStartdate = false;
   @track isSyncVisible = false;
   @track isScheduleVisible = false;
   @track openScheduleSchedule = false;
   @track isSyncprocess = true;
   @track currentStep = ''; // Initial step
   @track hasError = false; // Track error state
   @track hascompletes = false;
   @track ishide = true;
   @track isViewStatus = true;
   @track isScheduleViewStatus = true;
   @track batchInitiateionProcess = false;
   @track isProcessCompleted = false;
   @track isrequired = false;
   @track selectedValue = '';
   @track isCheck = false;
   @track headerlabel = 'Provide Email Address';
   @track jobName = '';
   @track syncJobName = '';
   @track cronExpression = '';
   @track toemails;
   @track toemailstosync;
   @track startdate;
   @track stopdate;
   @track monthofweekvalue;
   @track time;
   @track firstNameFilter = '';
   @track lastNameFilter = '';
   wiredQuery;
   @track isModalOpen = false;
   @track isSyncLoading = false;
   @track jobId;
   @track jobStatus;
   @track recordsProcessed = 0;
   @track recordsRetrieved = 0;
   @track searchKey = '';


   @track savequerycolumns = [
        { label: 'Label', fieldName: 'Label__c', type: 'text', sortable: true, initialWidth: 126, wrapText: true},
        { label: 'API Name', fieldName: 'Object_API_Name__c', type: 'text',  initialWidth: 126, wrapText: true},
        { label: 'Query', fieldName: 'Query__c', type: 'text', editable: true, initialWidth: 542, wrapText: true},
        { label: 'Last Modified Date', fieldName: 'LastModifiedDate', type: 'date', sortable: true, initialWidth: 163, wrapText: true,
                typeAttributes:{
                  year: "numeric",
                  month: "long",
                  day: "2-digit"
            }},
        {
            type: 'button-icon',
            typeAttributes: {
                iconName: 'utility:delete',
                label: 'Delete',
                alternativeText: 'Delete',
                name: 'delete',
                variant: 'container'
            },
           initialWidth: 80
        },
        {
            type: 'button-icon',
            typeAttributes: {
                iconName: 'utility:choice',
                label: 'Choose',
                alternativeText: 'Choose',
                name: 'choose',
                variant: 'container'
            },
            initialWidth: 80
        }
    ];


   get frequencyoptions() {
      return [{
            label: 'Once',
            value: 'once'
         },
         {
            label: 'Weekly',
            value: 'weekly'
         },
         {
            label: 'Monthly',
            value: 'monthly'
         },
      ];
   }

   get everyweekoptions() {
      return [{
            label: 'Sunday',
            value: '1'
         },
         {
            label: 'Monday',
            value: '2'
         },
         {
            label: 'Tuesday',
            value: '3'
         },
         {
            label: 'Wednesday',
            value: '4'
         },
         {
            label: 'Thursday',
            value: '5'
         },
         {
            label: 'Friday',
            value: '6'
         },
         {
            label: 'Saturday',
            value: '7'
         }
      ];
   }

   get monthofweekOptions() {
      return [{
            label: 'the 1st',
            value: '1'
         },
         {
            label: 'the 2nd',
            value: '2'
         },
         {
            label: 'the 3rd',
            value: '3'
         },
         {
            label: 'the 4th',
            value: '4'
         },
         {
            label: 'the last',
            value: '5'
         },
      ];
   }

   get monthofdayoptions() {
      return [{
            label: 'Sunday',
            value: '1'
         },
         {
            label: 'Monday',
            value: '2'
         },
         {
            label: 'Tuesday',
            value: '3'
         },
         {
            label: 'Wednesday',
            value: '4'
         },
         {
            label: 'Thursday',
            value: '5'
         },
         {
            label: 'Friday',
            value: '6'
         },
         {
            label: 'Saturday',
            value: '7'
         }
      ];
   }

   get syncOptions(){
      return [{
         label: 'Batch',
         value: 'Batch'
      },
      {
         label: 'Bulk',
         value: 'Bulk'
      }];
   }

   @wire(getObjects)
   wiredObjects({
      error,
      data
   }) {
      this.isLoading = true;
      if (data) {
         this.objects = data.map(obj => ({
            label: obj.label,
            value: obj.apiName
         }));
         this.isLoading = false;
      } else if (error) {
         this.showToast('Error', error, 'error');
         this.isLoading = false;
      }
   }

   @wire(getFields, {
      objectApiName: '$selectedObject'
   })
   wiredFields({
      error,
      data
   }) {
      this.isLoading = true;
      if (data) {
         this.fields = data;
         if (this.fields != null) {
            this.isdisable = false;
            this.updateVisibleFields();
            this.isFieldsLoading = false;
            this.isLoading = false;
         }
      } else if (error) {
         this.showToast('Error', error, 'error');
         this.isFieldsLoading = false;
         this.isLoading = false;
      }
   }

   @wire(getSandboxes)
   wiredCredentials({
      error,
      data
   }) {
      if (data) {
         this.credentialsoptions = data.map(credential => {
            return {
               label: credential.MasterLabel,
               value: credential.Id,
               clientId: credential.Client_Id__c,
               clientSecret: credential.Client_Secret__c,
               endpointURL: credential.Endpoint_URL__c,
               password: credential.Password__c,
               secretToken: credential.Secret_Token__c,
               username: credential.Username__c
            };
         });
      if (this.credentialsoptions.length > 0) {
             this.selectedCredential = this.credentialsoptions[0].value;
             this.selectedcredentialsValue = JSON.stringify(this.credentialsoptions[0]);
         }
      } else if (error) {
         this.showToast('Error', error, 'error');
      }
   }

   @wire(getQueryBanks)
   wiredQueryBanks(result) {
      this.isLoading = true; 
      this.wiredQuery = result;
      if (result.data) {
         this.queryBanks = result.data;
         this.isLoading = false;
         this.showqueryBanks = result.data.length > 0;
      } else if (result.error) {
         this.showToast('Error', result.error.body.message, 'error');
         this.queryBanks = [];
         this.isLoading = false; 
         this.showqueryBanks = false;
      } else {
         this.queryBanks = [];
         this.isLoading = false; 
         this.showqueryBanks = false;
      }
   }

   handleObjectChange(event) {
      this.selectedObject = event.detail.value;
      this.query = '';
      this.sourceField = '';
      this.targetField = '';
      this.fields = [];
      this.queryResults = [];
      this.visibleFields = [];
      this.showMoreButton = false;
      this.isFieldsLoading = true;
      this.fetchExternalIdFields(this.selectedObject);
   }

   handleFieldChange(event){
      this.sourceField = event.detail.value;
   }

   handletargetFieldChange(event){
      this.targetField = event.detail.value;
   }

   updateVisibleFields() {
      this.visibleFields = this.fields.slice(0, this.itemsToShow);
      this.showMoreButton = this.fields.length > this.itemsToShow;
   }

   handleShowMore() {
      this.itemsToShow += 10;
      this.updateVisibleFields();
   }

   handleQueryChange(event) {
      this.showfields = true;
      this.isvisible = false;
      this.selectedcredentialsValue = '';
      this.selectedCredential = '';
      this.isorgselection = true;
      this.query = event.target.value; //.trim();
      if (this.query.length >= 2) { // Perform search only after 2 or more characters
            this.fetchFields();
            this.isexecute = false;
        } else {
            this.fields = [];
         }
      /* else {
           this.visibleFields = this.fields.slice(0, this.itemsToShow);
       }
       if (this.visibleFields.length === 0) {
           this.visibleFields = [];
       }
       this.showMoreButton = this.fields.length > this.itemsToShow;*/
   }

   fetchFields() {
        getFields({ objectApiName: this.objectApiName, searchKey: this.searchKey })
            .then(result => {
                this.fields = result;
            })
            .catch(error => {
                console.error('Error fetching fields:', error);
            });
   }

   fetchExternalIdFields(objectApiName) {
      /*getExternalIdFields({ objectName: this.selectedObject, query: query })
            .then(result => {
               console.log('result----'+JSON.stringify(result));
               this.externalIdFields = result;
               console.log('Editable Fields:', this.externalIdFields);
            })
            .catch(error => {
               console.error('Error fetching fields:', error);
               this.showToast('Error', error.body.message, 'error');
            });*/
      getExternalIdFields({ objectApiName })
         .then(result => {
               this.externalIdFields = result.map(field => {
                  return { label: field, value: field };
               });

               this.tragerextIdFields = result
                  .filter(field => field.toLowerCase() !== 'id') // Exclude 'ID'
                  .map(field => {
                        return { label: field, value: field }; 
                  });

         })
         .catch(error => {
               this.showToast('Error', error.body.message, 'error');
               this.externalIdFields = [];
               this.tragerextIdFields = []; 
         })
         .finally(() => {
               this.isFieldsLoading = false;
         });
   }

   handleFieldClick(event) {
      const field = event.target.dataset.field;
      if (field) {
         if (this.query.includes(field)) return;

         if (this.query.includes('SELECT')) {
            if (this.query.includes('FROM')) {
               this.query = this.query.replace('FROM', `, ${field} FROM`);
            } else {
               this.query += `, ${field}`;
            }
         } else {
            this.query = `SELECT ${field} FROM ${this.selectedObject}`;
         }
      }
   }

   async handleExecuteQuery() {
      if (this.query == null) {
         this.showToast('Error', 'Please enter a valid SOQL query.', 'error');
         return;
      }

      try {
         this.isorgselection = false;
         this.showfields = false;
         this.isLoading = true;
         const data = await executeQuery({
            query: this.query,
            objectName: this.selectedObject
         });
         this.queryResults = data;
         if (data && data.length > 0) {
            this.columns = Object.keys(data[0])
            .filter(key => key !== 'MyExtId__c')
            .map(key => ({
               label: key,
               fieldName: key,
               type: 'text'
            }));
            this.hideFields = false;
         }
      } catch (error) {
         this.showToast('Error', error.body.message, 'error');
      } finally {
         this.isLoading = false;
      }
   }

   handleSaveQuery() {
      this.isLoading = true;
      createQueryRecord({ 
         label: this.selectedObject, 
         objectApiName: this.selectedObject, 
         query: this.query 
      })
      .then((result) => {
         this.isLoading = false;
         if(this.toastshow == false){
            this.showToast('Success', 'Query saved successfully.', 'success');
            return refreshApex(this.wiredQuery);
         }
         if (result) {
               this.savedQueryrecordId = result;
               return refreshApex(this.wiredQuery);
         } else {
               this.showToast('Error', 'Error creating query record.', 'error');
         }
      })
      .catch((error) => {
         this.isLoading = false;
         this.showToast('Error', error.body.message || 'Error creating query record.', 'error');
      });
   }

   handleSelected(event) {
      this.selectedValue = event.target.value;
   }

   handleChecked(event) {
      this.isCheck = event.target.checked;
   }

   buildCronExpression() {
      let [hours, minutes] = this.time.split(':');

      // Validate hours and minutes
      if (isNaN(hours) || isNaN(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
         this.showToast('Error', 'Invalid time format. Ensure time is in HH:mm and within valid ranges.', 'error');
         return false;
      }

      this.cronExpression = '';

      // Cron expression based on frequency
      switch (this.frequencyvalue) {
         case 'once':
            this.cronExpression = `0 ${minutes} ${hours} * * ?`; // At a specific time, once
            break;

         case 'weekly':
            if (!this.everyweekvalue || this.everyweekvalue.length === 0) {
               this.isSchduleLoading = false;
               this.showToast('Error', 'Weekly day value is missing', 'error');
               return false;
            }
            this.cronExpression = `0 ${minutes} ${hours} ? * ${this.everyweekvalue.join(',')}`; // Every week on specified day(s)
            break;

         case 'monthly':
            if (this.monthofdayvalue && !this.monthofweekvalue) {
               this.cronExpression = `0 ${minutes} ${hours} ${this.monthofdayvalue} * ?`; // On specific day(s) of the month
            } else if (this.monthofdayvalue && this.monthofweekvalue.length > 0) {
               this.cronExpression = `0 ${minutes} ${hours} ? * ${this.monthofdayvalue}#${this.monthofweekvalue}`; // e.g., "0 0 10 ? * 1#1" for the first Monday
            } else {
               this.isSchduleLoading = false;
               this.showToast('Error', 'Monthly value is missing. Please provide either days or weeks.', 'error');
               return false;
            }
            break;

         default:
            return false;
      }

      /*if (!this.isValidCronExpression(this.cronExpression)) {
          this.showToast('Error', 'cron expression is invalid.', 'error');
          return false;
      }*/

      return true;
   }

   isValidCronExpression(cron) {
      const cronRegex = /^(\d+|\*) (\d+|\*) (\d+|\?|\*) (\d+|\*) (\d+|\*|\d+(,\d+)*|(\d+#[1-5]))$/;
      return cronRegex.test(cron);
   }

   handleCredentialsChange(event) {
      this.selectedCredential = event.target.value;
      this.selectedcredentialsValue = JSON.stringify(this.credentialsoptions.find(cred => cred.value === this.selectedCredential));
      console.log('selectedcredentialsValue------'+this.selectedcredentialsValue);
      if (this.selectedcredentialsValue != null) {
         this.isvisible = true;
      }
   }

   handleSchedule() {
      this.isModalVisible = true;
      const now = new Date();
      const options = {
         hour: '2-digit',
         minute: '2-digit',
         hour12: false
      };
      this.time = now.toLocaleTimeString('en-GB', options);

      const today = new Date();
      const year = today.getFullYear();
      const month = String(today.getMonth() + 1).padStart(2, '0');
      const day = String(today.getDate()).padStart(2, '0');

      // Create tomorrow's date
      const tomorrowDate = new Date(today);
      tomorrowDate.setDate(today.getDate() + 1);
      const tomorrowYear = tomorrowDate.getFullYear();
      const tomorrowMonth = String(tomorrowDate.getMonth() + 1).padStart(2, '0');
      const tomorrowDay = String(tomorrowDate.getDate()).padStart(2, '0');

      this.startdate = `${year}-${month}-${day}`;
      this.stopdate = `${tomorrowYear}-${tomorrowMonth}-${tomorrowDay}`;
   }

   handleJobName(event) {
      this.jobName = event.detail.value;
   }

   handleSyncJobName(event) {
      this.syncJobName = event.detail.value;
   }

   handlefrequency(event) {
      this.frequencyvalue = event.detail.value;
      if (this.frequencyvalue == 'weekly') {
         this.isweekly = true;
         this.ismonthly = false;
         this.showStopdate = true;
         this.showStartdate = true;
      } else if (this.frequencyvalue == 'monthly') {
         this.isweekly = false;
         this.ismonthly = true;
         this.showStopdate = true;
         this.showStartdate = true;
      } else if (this.frequencyvalue == 'once') {
         this.isweekly = false;
         this.ismonthly = false;
         this.showStopdate = false;
         this.showStartdate = false;
      }
   }

   handleeveryweek(event) {
      this.everyweekvalue = event.detail.value;
   }


   handleInputChange(event) {
      const field = event.target.name;
      if (field === 'input1') {
         this.startdate = event.target.value;
      } else if (field === 'input2') {
         this.stopdate = event.target.value;
      } else if (field === 'input3') {
         this.time = event.target.value;
      }
   }

   handlemonthofweekChange(event) {
      this.monthofweekvalue = event.detail.value;
   }

   handlemonthofday(event) {
      this.monthofdayvalue = event.detail.value;
   }

   handletoemailsChange(event) {
      this.toemails = event.detail.value;
   }

   handletoemailssyncChange(event) {
      this.toemailstosync = event.detail.value;
   }

   async handleSave() {
      this.isSchduleLoading = true;
      this.toastshow = true;
      this.handleSaveQuery();
      const validationResponse = await validateSync({
         querys: this.query,
         objectName: this.selectedObject
      });
      if (validationResponse !== 'Valid') {
         this.isSchduleLoading = false;
         this.showToast('Error', validationResponse, 'error');
         return;
      }
      scheduleWeeklySync({
            query: this.query,
            objectName: this.selectedObject,
            toEmails: this.toemails,
            jobName: this.jobName,
            cronExp: this.cronExpression,
            savedQueryrecordId: this.savedQueryrecordId
         })
         .then((result) => {
            result = result;
            this.isSchduleLoading = false;
            this.isProcessCompleted = false;
            this.handleStep3();
            this.isModalVisible = false;
            this.isScheduleVisible = true;
         })
         .catch((error) => {
            this.isSchduleLoading = false;
            this.showToast('Error', error.body.message, 'error');
         });
   }

   async handleSync() {
      this.isSyncLoading = true;
      this.toastshow = true;
      this.handleSaveQuery();
      if (!this.validateEmails(this.toemailstosync)) {
         this.isSyncprocess = true;
         this.isSyncLoading = false;
         this.showToast('Error', 'Please provide valid email addresses, separated by commas.', 'error');
         return;
      }
      const validationResponse = await validateSync({
         querys: this.query,
         objectName: this.selectedObject
      });
      if (validationResponse !== 'Valid') {
         this.isSyncprocess = true;
         this.isSyncLoading = false;
         this.showToast('Error', validationResponse, 'error');
         return;
      }
      initiateOnDemandSync({
            query: this.query,
            objectName: this.selectedObject,
            toEmails: this.toemailstosync,
            savedQueryrecordId: this.savedQueryrecordId
         })
         .then((result) => {
            result = result;
            this.isSyncLoading = false;
            this.isSyncprocess = false;
            this.headerlabel = 'Sync Process';
            this.batchInitiateionProcess = true;
            this.isProcessCompleted = false;
            this.handleStep1();
         })
         .catch((error) => {
            this.showToast('Error', error.body.message, 'error');
            console.log('error----' + error.body.message);
            this.isSyncLoading = false;
         });
   }

   handleCancel() {
      this.jobName = '';
      this.headerlabel = '';
      this.toemails = '';
      this.toemailstosync = '';
      this.monthofweekvalue =  '';
      this.monthofdayvalue = '';
      this.toemailstosync = '';
      this.everyweekvalue = '';
      this.frequencyvalue = '';
      this.syncJobName = '';
      this.time = '';
      this.stopdate = '';
      this.startdate = '';
      this.isSyncprocess = true;
      this.isModalVisible = false;
      this.isSyncVisible = false;
      this.isScheduleVisible = false;
      this.batchInitiateionProcess = false;
      this.dispatchEvent(new CustomEvent('cancel'));
      this.dispatchEvent(new RefreshEvent());
   }

   openemaolmodel() {
      if(!this.selectedValue) {
         this.isrequired = true;
         this.showToast('Error', 'Please select a sync process: Bulk or Batch.', 'error');
      } else {
         this.isrequired = false;
         this.isSyncVisible = true;
      }
   }

   openScheduleProcess() {
      this.isSchduleLoading = true;
      console.log('1----');

      if (!this.buildCronExpression()) {
         this.isSchduleLoading = false;
         return;
      }
      this.handleSave();
   }

   validateEmails(emails) {
      const emailPattern = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
      const emailArray = emails.split(',');

      for (let email of emailArray) {
         if (!emailPattern.test(email.trim())) {
            return false;
         }
      }
      return true;
   }

   handleStep1() {
      if (!this.isProcessCompleted) {
         this.currentStep = '1';
         setTimeout(() => {
            this.handleStep2();
         }, 5000);
      }
   }

   handleStep2() {
      this.currentStep = '2';
      this.isViewStatus = false;
      this.showToast('Success', 'Sync Process Initiated Complete.', 'success');
   }

   handleSyncViewStatus() {
      this.isSyncVisible = false;
      this.beginRefresh();
      this[NavigationMixin.Navigate]({
         type: 'standard__navItemPage',
         attributes: {
            apiName: 'Sync_Batch_Job'
         }
      });
      this.dispatchEvent(new RefreshEvent());
   }

   handleStep3() {
      console.log('4----');
      if (!this.isProcessCompleted) {
         this.currentStep = '3';
         setTimeout(() => {
            this.handleStep4();
         }, 5000);
      }
   }

   handleStep4() {
      this.currentStep = '4';
      this.isProcessCompleted = true;
      this.isScheduleViewStatus = false;
      this.showToast('Success', 'Schedule Process Initiated Complete.', 'success');
   }

   handleViewStatus() {
      this.isScheduleVisible = false;
      this.beginRefresh();
      this[NavigationMixin.Navigate]({
         type: 'standard__navItemPage',
         attributes: {
            apiName: 'Sync_Schdeule_Jobs'
         }
      });
      this.dispatchEvent(new RefreshEvent());
   }

   handleSelectSoql(){
      this.showSavedQueries = true;
   }

   handlInlineeSave(event) {
    this.isQueryLoading = true;
    const updatedFields = event.detail.draftValues;

    updateRecords({ data: updatedFields})
        .then((result) => {
            result = result
             this.showToast('Success', result, 'success');
             this.draftValues = [];
             this.handleRefresh();
        })
        .catch(error => {
            console.error('Error updating records:', error);
            this.showToast('Error', 'Error updating records: ' + error.body.message, 'error');
        })
        .finally(() => {
            this.draftValues = [];
             this.isQueryLoading = false;
              return refreshApex(this.wiredQuery);
        });
   }

   handleclose() {
      this.showSavedQueries = false;
   }

   handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row.Id;
        const rowQuery = event.detail.row.Query__c;
        switch (actionName) {
            case 'delete':
                this.handleDelete(row);
                break;
            case 'choose':
                this.handleChoose(rowQuery);
                break;
            default:
        }
   }

   handleDelete(rows) {
        this.isQueryLoading = true;
        console.log('Delete action for rows:', rows);
         const recordIds = rows.split(',').map(id => id.trim());
         deleteRecords({ recordIds })
         .then((result) => {
            if(result.includes('No record IDs provided') || result.includes('No records found for the provided IDs')){
               this.showToast('Warning', result, 'warning');
            } else {
               this.showToast('Success', result, 'success');
               this.selectedRows = null;
               this.updateDeleteButtonState();
               return refreshApex(this.wiredQuery);
            }
         })
         .catch(error => {
            this.showToast('Error', 'Error deleting record: ' + error.body.message, 'error');
            this
         })
         .finally(() => {
            this.isQueryLoading = false;
            return refreshApex(this.wiredQuery);
         });
    }

   handleChoose(row) {
      const rowQuery = row;
      this.query = rowQuery;
      this.showSavedQueries = false;
      this.isexecute = false;
      this.showfields = true;
   }

   handleRefresh() {
      console.log('Data refreshed!');
      this.showToast('Success', 'Refresh Successfully.!', 'success');
      return refreshApex(this.wiredQuery);
   }

   handleSelectAll(event) {
      this.selectedRows = event.detail.selectedRows;
      this.updateDeleteButtonState();

      if (this.selectedRows.length > 0) {
         this.selectedRowId = this.selectedRows.map(row => row.Id).join(','); 
      } else {
         this.selectedRowId = null;
      }
   }

   handleDeleteSelected() {
      if (this.selectedRowId) {
         this.handleDelete(this.selectedRowId);
      } else {
         console.error('No row selected for deletion.');
      }
   }

   updateDeleteButtonState() {
        this.isDeleteButtonDisabled = this.selectedRows.length === 0;
   }

   handleDownload() {
      const recordIds = this.selectedRows.map(row => row.Id);
      
      startBulkDataLoaderJob({ recordIds })
         .then((response) => {
               this.jobId = response.jobId;
               this.jobStatus = response.jobStatus; 
               this.recordsProcessed = response.recordsProcessed;
               this.recordsRetrieved = response.recordsRetrieved || 0;
               this.isModalOpen = true;
               this.checkJobStatus();
         })
         .catch((error) => {
               this.showToast('Error', 'Error starting the download job: ' + error.body.message, 'error');
         });
   }

   checkJobStatus() {
      const interval = setInterval(() => {
         checkBulkJobStatus({ jobId: this.jobId })
               .then((statusResponse) => {
                  this.jobStatus = statusResponse.jobStatus;
                  this.recordsProcessed = statusResponse.recordsProcessed;
                  this.recordsRetrieved = statusResponse.recordsRetrieved;
                  if (this.jobStatus === 'JobComplete') {
                     clearInterval(interval);
                     closeModal();
                  }
               })
               .catch((error) => {
                  clearInterval(interval);
                  this.showToast('Error', 'Error checking job status: ' + error.body.message, 'error');
               });
      }, 5000); 
   }

   closeModal() {
      this.isModalOpen = false;
   }

  beginRefresh() {
    this.dispatchEvent(new RefreshEvent());
  }

   showToast(title, message, variant) {
      const evt = new ShowToastEvent({
         title: title,
         message: message,
         variant: variant
      });
      this.dispatchEvent(evt);
   }
}