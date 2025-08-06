--
-- Package_Body "EBA_DEMO_APPR"
--
CREATE OR REPLACE EDITIONABLE PACKAGE BODY "APPTESTEXAMPLE"."EBA_DEMO_APPR" as
    c_app_date_fmt constant varchar2(20) := 'APP_DATE_TIME_FORMAT';
    c_app_id       constant varchar2(6) := 'APP_ID';

    procedure update_laptop_request(
                p_id                      in number,
                p_status                  in varchar2 default null,
                p_workflow_id             in number   default null,
                p_approval_task_id        in number   default null,
                p_delivery_action_task_id in number   default null,
                p_approver                in varchar2 default null,
                p_decision_date           in date default null)
    is
    begin
       update EBA_DEMO_APPR_LAPTOP_REQUESTS
          set status                  = coalesce(p_status, status),
              workflow_id             = coalesce(p_workflow_id, workflow_id),
              approval_task_id        = coalesce(p_approval_task_id, approval_task_id),
              delivery_action_task_id = coalesce(p_delivery_action_task_id, delivery_action_task_id),
              approver                = coalesce(p_approver, approver),
              decision_date           = coalesce(p_decision_date, decision_date)
        where id                      = p_id;
       commit;
    end update_laptop_request;

    function get_participant_for_role(
                p_task_def_static_id in varchar2,
                p_job                in varchar2,
                p_proposed_sal       in number,
                p_role               in varchar2)
                return                  varchar2
    is
        l_ret varchar2(4000);
        l_include_fallback_entries boolean := false;
        l_current_user varchar2(200) := apex_application.g_user;
    begin
        for j in (select username,job_codes
                    from eba_demo_appr_approvers
                    where task_def_static_id = upper(p_task_def_static_id)
                    and (job_codes is null
                         or p_job is null
                         or (':'||job_codes||':' like '%:'||upper(p_job)||':%')
                        )
                    and (min_salary <= p_proposed_sal or min_salary is null)
                    and participant_role = p_role
                    and (participant_role = 'ADMIN' or username != l_current_user)
                    order by job_codes nulls last
                   ) loop
            -- Only include the fallback entries with null JOB_CODES
            -- if no more specific ones found
            if j.job_codes is null
               and not l_include_fallback_entries
               and l_ret is null then
                l_include_fallback_entries := true;
            end if;
            if j.job_codes is not null or l_include_fallback_entries then
                if l_ret is not null then
                    l_ret := l_ret ||',';
                end if;
                l_ret := l_ret || j.username;
            end if;
        end loop;
        return l_ret;
    end get_participant_for_role;

    function get_approver_for(
                p_task_def_static_id in varchar2,
                p_empno              in number,
                p_job                in varchar2,
                p_proposed_sal       in number)
                return                  varchar2
    is
    begin
        return get_participant_for_role(p_task_def_static_id,
                                        p_job,
                                        p_proposed_sal,
                                        'APPROVER');
    end get_approver_for;

    function get_admin_for(
                p_task_def_static_id in varchar2,
                p_job                in varchar2,
                p_proposed_sal       in number)
                return                  varchar2
    is
    begin
        return get_participant_for_role(p_task_def_static_id,
                                        p_job,
                                        p_proposed_sal,
                                        'ADMIN');
    end get_admin_for;

    function get_admin_for(
                p_task_def_static_id in varchar2,
                p_empno              in number,
                p_job                in varchar2,
                p_proposed_sal       in number)
                return                  varchar2
    is
    begin
        return get_participant_for_role(p_task_def_static_id,
                                        p_job,
                                        p_proposed_sal,
                                        'ADMIN');
    end get_admin_for;

    function user_has_open_approvals
                return boolean is
        l_app_user varchar2(30) := apex_application.g_user;
    begin
        for j in (select null
                   from apex_task_participants tp
                   left join apex_tasks t on t.task_id = tp.task_id
                   where tp.participant = l_app_user
                   and t.state_code in ('UNASSIGNED','ASSIGNED')
                   and tp.participant_type = 'POTENTIAL_OWNER'
                   and (t.initiator is null or t.initiator != l_app_user)
                   fetch first row only) loop
            apex_debug.info('### Returning true for user %s '||
                            'having open approvals tasks',l_app_user);
            return true;
        end loop;
        return false;
    end user_has_open_approvals;

    function user_has_open_admin_tasks
                return boolean is
        l_app_user varchar2(30) := apex_application.g_user;
    begin
        for j in (select null
                   from apex_task_participants tp
                   left join apex_tasks t on t.task_id = tp.task_id
                   where tp.participant = l_app_user
                   and t.state_code in ('UNASSIGNED','ASSIGNED')
                   and tp.participant_type = 'BUSINESS_ADMIN'
                   fetch first row only) loop
            apex_debug.info('### Returning true for user %s '||
                            'having open admin tasks',l_app_user);
            return true;
        end loop;
        return false;
    end user_has_open_admin_tasks;

    function details_task_url(
                p_app_id  in number,
                p_task_id in number,
                p_url     in varchar2)
                return       varchar2
    is
    begin
        return apex_plugin_util.replace_substitutions (
                    p_value => replace(replace(p_url, '&APP_ID.', p_app_id), '&TASK_ID.', p_task_id),
                    p_escape => false);
    end details_task_url;

    procedure validate_admin_and_approver(
                p_task_def_static_id in varchar2,
                p_empno              in number,
                p_proposed_sal       in number,
                p_admin             out varchar2,
                p_approver          out varchar2)
    is
        l_job eba_demo_appr_emp.job%type;
    begin
        select job
        into l_job
        from eba_demo_appr_emp
        where empno = p_empno;
        p_admin := get_admin_for(p_task_def_static_id,
                                 p_empno,
                                 l_job,
                                 p_proposed_sal);
        p_approver := get_approver_for(p_task_def_static_id,
                                       p_empno,
                                       l_job,
                                       p_proposed_sal);
    end validate_admin_and_approver;

    /*
     * Workaround for RDBMS 21c issue directly using listagg() against view w/ json_table()
     */
    function admins_for_task(
                p_task_id in number)
                return       varchar2
    is
        l_ret varchar2(2000);
    begin
        -- Return admins as CSV
        select listagg(participant,', ')
               within group (order by participant)
        into l_ret
        from apex_task_participants
        where task_id = p_task_id
        and participant_type = 'BUSINESS_ADMIN';
        return l_ret;
    end admins_for_task;

    function approvers_for_task(
                p_task_id in number)
                return       varchar2
    is
        l_ret varchar2(2000);
    begin
        -- Return approvers as CSV leaving out initiator
        select listagg(participant,', ')
               within group (order by participant)
        into l_ret
        from apex_task_participants tp, apex_tasks t
        where tp.task_id = p_task_id
        and t.task_id = tp.task_id
        and participant_type = 'POTENTIAL_OWNER'
        and (   t.initiator is null
             or t.initiator_can_complete = 'Y'
             or (t.initiator_can_complete = 'N' and t.initiator != tp.participant));
        return l_ret;
    end approvers_for_task;

    function get_laptop_approver(
                p_renewal_count number)
                return          varchar2
    is
    begin
        return
          case p_renewal_count
            when 0 then 'JANE'
            when 1 then 'STEVE'
            else 'BO'
          end;
    end get_laptop_approver;

    function get_appraisal_participant(
            p_appraisal_id in number)
            return            varchar2
    is
        l_ret varchar2(4000);
    begin
        select e.ename
        into   l_ret
        from eba_demo_appr_appraisals a
        left join eba_demo_appr_emp e on e.empno = a.empno
        where id = p_appraisal_id;
        return l_ret;
    exception
        when no_data_found then
            return null;
    end get_appraisal_participant;

    function get_appraisal_manager(
                p_appraisal_id in number)
                return            varchar2
    is
        l_ret varchar2(4000);
    begin
        select m.ename
          into l_ret
          from eba_demo_appr_appraisals a
          left join eba_demo_appr_emp e on e.empno = a.empno
          left outer join eba_demo_appr_emp m on m.empno = e.mgr
         where a.id = p_appraisal_id;
          return l_ret;
    exception
        when no_data_found then
            return null;
    end get_appraisal_manager;

    procedure determine_appraisal_vp(
                p_appraisal_id in number,
                p_vp_username  in out varchar2)
    is
    begin
        if p_vp_username is null then
            select m2.ename
              into p_vp_username
              from eba_demo_appr_appraisals a
              left join eba_demo_appr_emp e on e.empno = a.empno
              left outer join eba_demo_appr_emp m on m.empno = e.mgr
              left outer join eba_demo_appr_emp m2 on m2.empno = m.mgr
             where a.id = p_appraisal_id;
            if p_vp_username is null then
                raise_application_error(-20001,'No second-level VP available for review.');
            end if;
        else
            if p_vp_username != 'NONE' then
                for emp_check in (select null
                                    from eba_demo_appr_emp
                                   where ename = p_vp_username) loop
                    return;
                end loop;
                raise_application_error(-20001,apex_string.format('%s is not a valid employee name.',p_vp_username));
            end if;
        end if;
    exception
        when no_data_found then
            null;
    end determine_appraisal_vp;

    function mask_for_date_page_item(p_item_name varchar2) return varchar2 is
        l_mask varchar2(200);
    begin
        select coalesce(format_mask,v(c_app_date_fmt))
        into l_mask
        from apex_application_page_items
        where application_id = v(c_app_id)
        and item_name = upper(p_item_name);
        return l_mask;
    end mask_for_date_page_item;
    --
    function dv(p_item_name varchar2) return date is
        l_mask varchar2(200) := mask_for_date_page_item(p_item_name);
    begin
        return to_date(v(p_item_name),l_mask);
    end dv;
    --
    function df(p_item_name varchar2, p_date date) return varchar2 is
        l_mask varchar2(200) := mask_for_date_page_item(p_item_name);
    begin
        return to_char(p_date,l_mask);
    end df;
    --
    function appraisal_period(
        p_start_date in date,
        p_end_date   in date)
        return          varchar2
    is
    begin
        return to_char(p_start_date,'FMMon YYYY')||
               ' → '||
               to_char(p_end_date,'FMMon YYYY');
    end appraisal_period;
    --
    procedure update_appraisal_status(
                p_id     in number,
                p_status in varchar2)
    is
    begin
        update eba_demo_appr_appraisals
        set status = upper(p_status)
        where id = p_id;
        case upper(p_status)
            when 'ORIGINATED' then
                update eba_demo_appr_appraisals
                set date_originated = sysdate
                where id = p_id;
            when 'SUBMITTED' then
                update eba_demo_appr_appraisals
                set input_completed = sysdate
                where id = p_id;
            when 'MGR_SUBMITTED' then
                update eba_demo_appr_appraisals
                set manager_completed = sysdate
                where id = p_id;
            when 'VP_REVIEWED' then
                update eba_demo_appr_appraisals
                set vp_review_date = sysdate
                where id = p_id;
            else
                null;
        end case;
    end update_appraisal_status;
    --
    function rejection_delay_until_time
    return date
    is
    begin
        return sysdate + 1/24/60;
    end;
    --
    procedure laptop_delivered(
                p_laptop_request_id in number)
    is
        pragma autonomous_transaction;
    begin
        --
        -- If the laptop request has a non-null order_id
        -- then it was not in stock and we had to order it
        -- 
        for j in (select workflow_id as laptop_request_workflow_id
                    from eba_demo_appr_laptop_requests
                   where id = p_laptop_request_id
                     and order_id is not null) loop
            --
            -- Lookup the task id of the action task used to
            -- confirm the receipt of the laptop order.
            -- It's stored in the V_ version variable of
            -- the LAPTOP_PROCUREMENT workflow invoked from
            -- the LAPTOP_REQUEST workflow
            -- 
            for k in (select workflow_id as procurement_workflow_id
                        from apex_workflows
                       where workflow_def_static_id = 'LAPTOP_PROCUREMENT'
                         and parent_workflow_id = j.laptop_request_workflow_id) loop
                apex_approval.complete_task(
                    p_task_id   => apex_workflow.get_variable_value(
                                    p_instance_id        => k.procurement_workflow_id,
                                    p_variable_static_id => 'V_DELIVERY_ACTION_TASK_ID'),
                    p_autoclaim => true);
            end loop;
        end loop;
    end;
    --
    function userlist_for_department(
                p_dname in varchar2)
                return     varchar2
    is
        l_ret varchar2(4000);
    begin
        select listagg(e.ename,',')
        into l_ret
        from eba_demo_appr_emp e
        left outer join eba_demo_appr_dept d
                     on d.deptno = e.deptno
        where d.dname = p_dname;
        return l_ret;
    end;
    --
    procedure add_business_admin(
        p_additional_participants in out nocopy apex_approval.t_task_participant_changes,
        p_taskdef_name            in varchar2,
        p_old                     in varchar2,
        p_new                     in varchar2,
        p_reason                  in varchar2 default null)
    is
        l_idx pls_integer := p_additional_participants.count + 1;
    begin
        p_additional_participants(l_idx) :=
            apex_approval.t_task_participant_change(
                apex_approval.t_task_participant(apex_approval.c_task_business_admin,
                                                 apex_approval.c_task_identity_type_user,
                                                 p_old),
                apex_approval.t_task_participant(apex_approval.c_task_business_admin,
                                                 apex_approval.c_task_identity_type_user,
                                                 p_new),
                coalesce(p_reason,
                         apex_string.format(
                            '%s temporarily covering %s business admin dutites',
                            p_new,
                            p_taskdef_name)));
    end add_business_admin;
    --
    procedure add_participant(
        p_additional_participants in out nocopy apex_approval.t_task_participant_changes,
        p_taskdef_name            in varchar2,
        p_old                     in varchar2,
        p_new                     in varchar2,
        p_reason                  in varchar2,
        p_wildcard                in boolean default false)
    is
        l_idx pls_integer := p_additional_participants.count + 1;
    begin
        p_additional_participants(l_idx) :=
            apex_approval.t_task_participant_change(
                apex_approval.t_task_participant(apex_approval.c_task_potential_owner,
                                                 apex_approval.c_task_identity_type_user,
                                                 p_old),
                apex_approval.t_task_participant(apex_approval.c_task_potential_owner,
                                                 apex_approval.c_task_identity_type_user,
                                                 p_new),
                coalesce(p_reason,
                         apex_string.format(
                            case
                                when p_wildcard then '%s helping to cover %s'
                                else      '%s covering %s for vacationing %s'
                            end,
                            p_new,
                            p_taskdef_name,
                            p_old)));
    end add_participant;
    --
    procedure handle_temp_business_admin(
        p_participants            in apex_approval.t_task_participants,
        p_taskdef_name            in varchar2,
        p_additional_participants in out nocopy apex_approval.t_task_participant_changes)
    is
        l_temp_business_admin varchar2(200) := apex_app_setting.get_value('TEMPORARY_BUSINESS_ADMIN');
    begin
        if l_temp_business_admin is not null then
            for j in 1..p_participants.count loop
                if     p_participants(j).type = apex_approval.c_task_business_admin
                   and p_participants(j).identity = apex_approval.c_task_identity_type_user then
                    add_business_admin(
                        p_additional_participants => p_additional_participants,
                        p_taskdef_name            => p_taskdef_name,
                        p_old                     => p_participants(j).value,
                        p_new                     => l_temp_business_admin);
                end if;
            end loop;
        end if;
    end handle_temp_business_admin;
        --
    function involved_participants(
        p_participants in apex_approval.t_task_participants)
        return            apex_t_varchar2
    is
        l_ret apex_t_varchar2;
    begin
        for j in 1..p_participants.count loop
            if     p_participants(j).type = apex_approval.c_task_potential_owner
               and p_participants(j).identity = apex_approval.c_task_identity_type_user then
                apex_string.push(l_ret,p_participants(j).value);
            end if;
        end loop;
        return l_ret;
    end;
    --
    function taskdef_name(
        p_task_def_static_id in varchar2)
        return                  varchar2
    is
        l_ret apex_appl_taskdefs.name%type;
    begin
        select name
        into l_ret
        from apex_appl_taskdefs
       where static_id = p_task_def_static_id
         and application_id = v('APP_ID');
       return l_ret;
    exception
        when no_data_found then
            return null;
    end taskdef_name;

    procedure approval_vacation_handler(
                p_param    in apex_approval.t_vacation_rule_input,
                p_result  out apex_approval.t_vacation_rule_result)
    is
        l_participants     apex_t_varchar2;
        l_taskdef_name     apex_tasks.task_def_name%type;
    begin
        l_taskdef_name := taskdef_name(p_param.task_def_static_id);
        handle_temp_business_admin(
            p_participants            => p_param.original_participants,
            p_taskdef_name            => l_taskdef_name,
            p_additional_participants => p_result.participant_changes);
        l_participants := involved_participants(p_param.original_participants);
        if l_participants.count > 0 then
            --
            -- Loop over vacation rows where the current date falls between the
            -- optional start/end dates and the "For Which Approval?" (task_def_ids)
            -- column includes the current taskdef id
            --
            for j in (select original_user,substitute_user,reason
                        from eba_demo_appr_vacation
                       where    (original_user is null
                             or original_user in (select column_value
                                                    from table(l_participants)))
                         and instr(':'||task_def_ids||':',':'||p_param.task_def_static_id||':') > 0
                         and nvl(start_date,sysdate) <= sysdate and nvl(end_date,sysdate) >= sysdate ) loop
                if j.original_user is null then
                    -- Treat a null original_user as a wildcard, so create a vacation
                    -- assignment for each of the original participants to be substituted
                    -- by the substitute_user
                    for k in 1..l_participants.count loop
                        add_participant(
                            p_additional_participants => p_result.participant_changes,
                            p_taskdef_name            => l_taskdef_name,
                            p_old                     => l_participants(k),
                            p_new                     => j.substitute_user,
                            p_reason                  => j.reason,
                            p_wildcard                => true);
                    end loop;
                else
                    add_participant(
                        p_additional_participants => p_result.participant_changes,
                        p_taskdef_name            => l_taskdef_name,
                        p_old                     => j.original_user,
                        p_new                     => j.substitute_user,
                        p_reason                  => j.reason);
                end if;
            end loop;
            p_result.has_participant_changes := p_result.participant_changes.count > 0;
        end if;
    end;

    procedure appraisal_vp_review_handler(
                p_param    in apex_approval.t_vacation_rule_input,
                p_result  out apex_approval.t_vacation_rule_result)
    is
        l_participants     apex_t_varchar2;
        l_taskdef_name     apex_tasks.task_def_name%type;
    begin
        l_taskdef_name := taskdef_name(p_param.task_def_static_id);
        handle_temp_business_admin(
            p_participants            => p_param.original_participants,
            p_taskdef_name            => l_taskdef_name,
            p_additional_participants => p_result.participant_changes);
        l_participants := involved_participants(p_param.original_participants);
        if l_participants.count > 0 then
            --
            -- Loop over usernames in the EMP_APPRAISAL_EXTRA_VP_REVIEWERS setting value
            --
            for j in (select column_value as substitute_user
                        from apex_string.split(apex_app_setting.get_value('EMP_APPRAISAL_EXTRA_VP_REVIEWERS'),':')) loop
                        add_participant(
                            p_additional_participants => p_result.participant_changes,
                            p_taskdef_name            => l_taskdef_name,
                            p_old                     => l_participants(1),
                            p_new                     => j.substitute_user,
                            p_reason                  => apex_string.format('Additional appraisal signoff %s',j.substitute_user));
            end loop;
            p_result.has_participant_changes := p_result.participant_changes.count > 0;
        end if;
    end appraisal_vp_review_handler;

    function laptop_in_stock(
        p_laptop_type in varchar2)
        return           boolean
    is
    begin
        for j in (select amount
                    from eba_demo_appr_laptop_stock
                   where laptop_type = upper(p_laptop_type)
                     and amount > 0) loop
            return true;
        end loop;
        return false;
    end laptop_in_stock;

    procedure deliver_laptop_from_stock(
        p_laptop_type       in varchar2,
        p_laptop_request_id in number)
    is
    begin
        update eba_demo_appr_laptop_stock
           set amount = amount - 1
         where laptop_type = upper(p_laptop_type);
         update eba_demo_appr_laptop_requests
            set status = 'DELIVERED',
                delivered_date = trunc(sysdate)
          where id = p_laptop_request_id;
    end deliver_laptop_from_stock;

    procedure order_laptop_from_supplier(
        p_laptop_type       in varchar2,
        p_laptop_request_id in number)
    is
    begin
        -- In this demo, we're simulating getting the order id
        -- to be a random number betwen 111111 and 999999, but in a real application
        -- this would place the order for a laptop of type p_laptop_type
        -- with the appropriate supplier and get back the order id number
        update eba_demo_appr_laptop_requests
           set order_id = trunc(dbms_random.value(1111111, 9999999)),
               order_date = trunc(sysdate)
        where id = p_laptop_request_id;
    end order_laptop_from_supplier;
end;
/