--
-- Package_Spec "EBA_DEMO_APPR"
--
CREATE OR REPLACE EDITIONABLE PACKAGE "APPTESTEXAMPLE"."EBA_DEMO_APPR" as
    --
    -- Return the approver username for Job Change task
    --
    function get_approver_for(
        p_task_def_static_id in varchar2,
        p_empno              in number,
        p_job                in varchar2,
        p_proposed_sal       in number)
        return                  varchar2;

    --
    -- Return the business admin username for Job Change task
    --
    function get_admin_for(
        p_task_def_static_id in varchar2,
        p_empno              in number,
        p_job                in varchar2,
        p_proposed_sal       in number)
        return                  varchar2;

    --
    -- Return the participant username of a self-appraisal
    --
    function get_appraisal_participant(
        p_appraisal_id in number)
        return            varchar2;

    --
    -- Return the manager username for employee being appraised
    --
    function get_appraisal_manager(
        p_appraisal_id in number)
        return            varchar2;

    --
    -- Return the VP username for employee being appraised
    --
    procedure determine_appraisal_vp(
        p_appraisal_id in number,
        p_vp_username  in out varchar2);

    --
    -- Return true if the current user has any open approvals
    --
    function user_has_open_approvals
                return boolean;

    --
    -- Return true if the current user has any open admin tasks
    --
    function user_has_open_admin_tasks
                return boolean;

    --
    -- Validate whether the combination of admin and approver is legal
    --
    procedure validate_admin_and_approver(
        p_task_def_static_id in varchar2,
        p_empno              in number,
        p_proposed_sal       in number,
        p_admin             out varchar2,
        p_approver          out varchar2);

    --
    -- Return the details task URL
    --
    function details_task_url(
        p_app_id  in number,
        p_task_id in number,
        p_url     in varchar2)
        return       varchar2;

    --
    -- Return the approvers for a task
    --
    function approvers_for_task(
        p_task_id in number)
        return       varchar2;

    --
    -- Return the admins for a task
    --
    function admins_for_task(
        p_task_id in number)
        return       varchar2;

    --
    -- Return the approver for laptop based on the renewal count
    --
    function get_laptop_approver(
        p_renewal_count in number)
        return             varchar2;

    --
    -- Update a laptop request with the provided information
    --
    procedure update_laptop_request(
        p_id                      in number,
        p_status                  in varchar2 default null,
        p_workflow_id             in number   default null,
        p_approval_task_id        in number   default null,
        p_delivery_action_task_id in number   default null,
        p_approver                in varchar2 default null,
        p_decision_date           in date default null);

    --
    -- Return the appraisal period in words
    --
    function appraisal_period(
        p_start_date in date,
        p_end_date   in date)
        return          varchar2;

    --
    -- Update the status of an appraisal
    --
    procedure update_appraisal_status(
        p_id     in number,
        p_status in varchar2);

    --
    -- Return the DATE value of the named page item
    --
    function dv(
        p_item_name in varchar2)
        return         date;

    --
    -- Return the formatted value of a date using the page item's mask
    --
    function df(
        p_item_name in varchar2,
        p_date      in date)
    return varchar2;

    --
    -- Return a date that is one minute later than the current time
    --
    function rejection_delay_until_time
    return date;

    --
    -- Complete the Laptop Delivered task whose ID is passed in
    --
    procedure laptop_delivered(
        p_laptop_request_id in number);

    --
    -- Returns a comma-separated list of usernames in the given department name
    --
    function userlist_for_department(
        p_dname in varchar2)
        return     varchar2;

    --
    -- Handles vacation reassignments.
    -- Configured as the Task Vacation Rule Procedure at application level
    --
    procedure approval_vacation_handler(
        p_param    in apex_approval.t_vacation_rule_input,
        p_result  out apex_approval.t_vacation_rule_result);

    --
    -- Handles additional VP Review assignments
    -- Configured as the Task Vacation Rule Procedure at TaskDef level
    -- on the "VP Review" action task.
    --
    procedure appraisal_vp_review_handler(
        p_param    in apex_approval.t_vacation_rule_input,
        p_result  out apex_approval.t_vacation_rule_result);

    --
    -- Return true if laptop type is in stock
    --
    function laptop_in_stock(
        p_laptop_type in varchar2)
        return           boolean;

    --
    -- Deliver a laptop from stock and decrement amount on hand
    --
    procedure deliver_laptop_from_stock(
        p_laptop_type       in varchar2,
        p_laptop_request_id in number);

    --
    -- Order a laptop
    --
    procedure order_laptop_from_supplier(
        p_laptop_type       in varchar2,
        p_laptop_request_id in number);
end;
/