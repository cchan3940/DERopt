%% Declaring decision variables and setting up cost function
yalmip('clear')
clear var*
Constraints=[];

T = length(time);     %t-th time interval from 1...T
% K = size(elec,2);     %k-kth building from 
M = length(endpts);   %# of months in the simulation

% Objective = [];

%% Utility Electricity
if isempty(utility_exists) == 0
    %%%Electrical Import Variables
    var_util.import = sdpvar(T,1,'full');
    
    %%%Demand Charge Variables
    %%%Only creating variables for # of months and number of applicable
    %%%rates, as defined with the binary dc_on input
    if sum(dc_exist)>0
        %%%Non TOU DC
        var_util.nontou_dc=sdpvar(M,1,'full');
        
        %%%On Peak/ Mid Peak TOU DC
        if onpeak_count > 0
            var_util.onpeak_dc=sdpvar(onpeak_count,1,'full');
            var_util.midpeak_dc=sdpvar(midpeak_count,1,'full');
        else
            var_util.onpeak_dc = 0;
            var_util.midpeak_dc = 0;
        end
    end
    
    %%% Cost of Imports + Demand Charges
    dc_count=1;
    
    %%%Allocating space
    temp_cf = zeros(size(elec));
    
%     for i=1:K %%%Going through all buildings
        %%%Find the applicable utility rate
        index=find(ismember(rate_labels,rate(1)));
        
        %%%Specifying cost function
%         temp_cf(:,i) = day_multi.*var_util.import_price(:,index);
%     end
    
    %%%Import Energy charges
%     Objective = sum(sum(var_util.import.*temp_cf));
    Objective = sum(sum(var_util.import.*(day_multi.*import_price(:,index))));

    %%%Clearing temporary cost function matrix
    clear temp_cf

    %     for i =1:K
    if dc_exist == 1
        %%%Find the applicable utility rate
        index=find(ismember(rate_labels,rate(1)));
        
        Objective =  Objective ...
            + sum(dc_nontou(index)*var_util.nontou_dc(:,dc_count))... %%%non TOU DC
            + sum(dc_on(index)*var_util.onpeak_dc(:,dc_count)) ... %%%On Peak DC
            + sum(dc_mid(index)*var_util.midpeak_dc(:,dc_count)); %%%Mid Peak DC
        %%% Utility_import * Demand_charge_rate
        
        %%%Index of DCs
        dc_count=dc_count+1;
    end
%     end   
    
else
    %%%Electrical Import Variables
    var_util.import=zeros(T,1);
    
    %%%Non TOU DC
    var_util.nontou_dc=zeros(M,1);
    
    %%%On Peak/ Mid Peak TOU DC
    var_util.onpeak_dc=zeros(onpeak_count,1);
    var_util.midpeak_dc=zeros(midpeak_count,1);
end


%% Technologies That Can Be Adopted at Each Building Energy Hub
%% Solar PV
if isempty(pv_v) == 0
    
    %%%PV Generation to meet building demand (kWh)
    var_pv.pv_elec = sdpvar(T,1,'full'); %%% PV Production sent to the building
    
    %%%Size of installed System (kW)
    var_pv.pv_adopt= sdpvar(1,size(pv_v,2),'full'); %%%PV Size
    
    if island == 0 && export_on == 1  %If grid tied, then include NEM and wholesale export
        
        %%% Variables that exist when grid tied
        var_pv.pv_nem = sdpvar(T,1,'full'); %%% PV Production exported w/ NEM
%         pv_wholesale = sdpvar(T,K,'full'); %%% PV Production exported under NEM rates
        
        %%%PV Export - NEM (kWh)       
            %%%Utility rates for building k
            index=find(ismember(rate_labels,rate(1)));


        %%%Adding values to the cost function
         Objective = Objective...
             + sum(sum((-day_multi.*export_price(:,index)).*var_pv.pv_nem)); %%%NEM Revenue Cost
         
         %%%Clearing temporary variables
         clear temp_cf1 temp_cf2
    else
        var_pv.pv_nem = [];
    end
    
    %%%PV Cost
%     mod_val = 0.7
%     mod_val*pv_cap
%      mod_val*(pv_v(1)*M*cap_mod.pv - cap_scalar.pv)
    Objective=Objective ...
        + sum(M*pv_mthly_debt'.*pv_cap_mod.*var_pv.pv_adopt)... %%%PV Capital Cost ($/kW installed)
        + pv_v(3)*(sum(sum(day_multi.*(var_pv.pv_elec + var_pv.pv_nem)))); %%%PV O&M Cost ($/kWh generated)
%         + pv_v(3)*(sum(sum(repmat(day_multi,1,K).*(var_pv.pv_elec + var_pv.pv_nem + pv_wholesale))) ); %%%PV O&M Cost ($/kWh generated)

    %%% Allow for adoption of Renewable paired storage when enabled (REES)
    if isempty(ees_v) == 0 && rees_on == 1
        
        %%%Adopted REES Size
        var_rees.rees_adopt= sdpvar(1,size(ees_v,2),'full');
        %var_rees.rees_adopt= semivar(1,K,'full');
        %%%REES Charging
        var_rees.rees_chrg=sdpvar(T,size(ees_v,2),'full');
        %%%REES discharging
        var_rees.rees_dchrg=sdpvar(T,size(ees_v,2),'full');
        
        %%%REES SOC
        var_rees.rees_soc=sdpvar(T,size(ees_v,2),'full');
        %%%REES Cost Functions 
        for ii = 1:size(ees_v,2)
            Objective = Objective...
                + sum(rees_mthly_debt(ii)*M.*rees_cap_mod(ii)'.*var_rees.rees_adopt(ii)) ...%%%Capital Cost
                + ees_v(2,ii)*sum(sum(day_multi.*var_rees.rees_chrg(:,ii)))... %%%Charging O&M
                + ees_v(3,ii)*(sum(sum(day_multi.*(var_rees.rees_dchrg(:,ii)))));%%%Discharging O&M
            
            if island ~= 1 % If not islanded, AEC can export NEM and wholesale for revenue
                %%%REES NEM Export
                %%%REES discharging to grid
                var_rees.rees_dchrg_nem=sdpvar(T,size(ees_v,2),'full');
                
                %%%Creating temp variables
                temp_cf = zeros(size(elec));
                
                %             for k = 1:K
                %%%Applicable utility rate
                index=find(ismember(rate_labels,rate(1)));
                
%                 temp_cf(:,k) = day_multi.*(ees_v(3,ii) - export_price(:,index));
                
                %             end
                %%% Setting objective function
                Objective = Objective...
                    + sum(sum((day_multi.*(ees_v(3,ii) - export_price(:,index))).*var_rees.rees_dchrg_nem(:,ii)));
                
            else
                var_rees.rees_dchrg_nem=zeros(T,1);
            end
        end
    else
        var_rees.rees_adopt=zeros(1,1);
        var_rees.rees_chrg=zeros(T,1);
        var_rees.rees_dchrg=zeros(T,1);
        var_rees.rees_dchrg_nem=zeros(T,1);
        var_rees.rees_soc=zeros(T,1);
    end
    
else
    var_pv.pv_adopt=zeros([1 1]);
    var_pv.pv_elec=zeros([T 1]);
    var_pv.pv_nem=zeros([T 1]);
    pv_wholesale=zeros([T 1]);
    var_rees.rees_adopt=zeros(1,1);
    var_rees.rees_chrg=zeros(T,1);
    var_rees.rees_dchrg=zeros(T,1);
    var_rees.rees_dchrg_nem=zeros(T,1);
    var_rees.rees_soc=zeros(T,1);
end
toc
%% Electrical Energy Storage
if isempty(ees_v) == 0
    
    %%%Adopted EES Size
    var_ees.ees_adopt= sdpvar(1,size(ees_v,2),'full');
    %var_ees.ees_adopt = semivar(1,K,'full');
    %%%EES Charging
    var_ees.ees_chrg=sdpvar(T,size(ees_v,2),'full');
    %%%EES discharging
    var_ees.ees_dchrg=sdpvar(T,size(ees_v,2),'full');
    %%%EES SOC
    var_ees.ees_soc=sdpvar(T,size(ees_v,2),'full');
    
    
    for ii = 1:size(ees_v,2)
        %%%EES Cost Functions
        Objective = Objective...
            + sum(ees_mthly_debt(ii)*M.*ees_cap_mod(ii)'.*var_ees.ees_adopt(ii)) ...%%%Capital Cost
            + ees_v(2,ii)*sum(sum(day_multi.*var_ees.ees_chrg(:,ii))) ...%%%Charging O&M
            + ees_v(3,ii)*sum(sum(day_multi.*var_ees.ees_dchrg(:,ii)));%%%Discharging O&M
    end
    %%%SGIP rates
    if sgip_on
        
% % %         Begin comments here
%         %%%Residential Credits
%         var_sgip.sgip_ees_npbi = sdpvar(1,sum((res_units>0).*(~low_income>0)),'full');
%         %%%Residential Equity Credits
%         var_sgip.sgip_ees_npbi_equity = sdpvar(1,sum(low_income>0),'full');
%         
%         Objective = Objective ...
%             - sum(sgip(3)*M*var_sgip.sgip_ees_npbi) ...
%             - sum(sgip(4)*M*var_sgip.sgip_ees_npbi_equity);
%         
%         if sum(sgip_pbi)>0
%             %%% Performance based incentives
%             var_sgip.sgip_ees_pbi = sdpvar(3,sum(sgip_pbi),'full');
%             
%             Objective = Objective ...
%                 - sum(sgip(2)*M*var_sgip.sgip_ees_pbi(1,:)) ...
%                 - sum(sgip(2)*0.5*M*var_sgip.sgip_ees_pbi(2,:)) ...
%                 - sum(sgip(2)*0.25*M*var_sgip.sgip_ees_pbi(3,:));
%         else
%             var_sgip.sgip_ees_pbi = zeros(3,1);
%         end
        
        %%% End Comments Here
    else
        var_sgip.sgip_ees_pbi = zeros(3,1);
        var_sgip.sgip_ees_npbi = 0;
        var_sgip.sgip_ees_npbi_equity = 0;
    end
    
else
    var_ees.ees_adopt = zeros(1,1);
    var_ees.ees_soc = zeros(T,1);
    var_ees.ees_chrg = zeros(T,1);
    var_ees.ees_dchrg = zeros(T,1);
end
toc

%% H2 Production and Storage

%%%Electrolyzer
if ~isempty(el_v)
    
    %%%Electrolyzer efficiency
    el_eff = ones(T,size(el_v,2));
    for ii = 1:size(el_v,2)
        el_eff(:,ii) = (1/el_v(3,ii)).*el_eff(:,ii);
    end
    
    %%%Adoption technologies
    var_el.el_adopt = sdpvar(1,size(el_v,2),'full');
    %%%Electrolyzer production
    var_el.el_prod = sdpvar(T,size(el_v,2),'full');
    
    for ii = 1:size(el_v,2)
        %%%Electrolyzer Cost Functions
        Objective = Objective...
            + sum(M.*el_mthly_debt.*var_el.el_adopt) ... %%%Capital Cost
            + sum(sum(var_el.el_prod).*el_v(2,:)); %%%VO&M
    end
    
    if ~isempty(h2es_v)
        %%%H2 Storage
        %%%Adopted EES Size
        var_h2es.h2es_adopt = sdpvar(1,size(h2es_v,2),'full');
        %var_ees.ees_adopt = semivar(1,K,'full');
        %%%EES Charging
        var_h2es.h2es_chrg = sdpvar(T,size(h2es_v,2),'full');
        %%%EES discharging
        var_h2es.h2es_dchrg = sdpvar(T,size(h2es_v,2),'full');
        %%%EES SOC
        var_h2es.h2es_soc = sdpvar(T,size(h2es_v,2),'full');
        for ii = 1:size(h2es_v,2)
            %%%Electrolyzer Cost Functions
            Objective = Objective...
                + sum(M.*h2es_mthly_debt.*var_el.el_adopt) ... %%%Capital Cost
                + sum(sum(var_h2es.h2es_chrg).*el_v(2,:)) ... %%%Charging Cost
                + sum(sum(var_h2es.h2es_dchrg).*el_v(3,:)); %%%Discharging Cost
        end
        
        h2_chrg_eff = 1 - h2es_v(8,:);
    end
    
else
    var_el.el_prod = zeros(T,1);
    var_h2es.h2es_chrg = zeros(T,1);
    var_h2es.h2es_dchrg = zeros(T,1);
    el_eff = zeros(T,1);
end

%% Legacy Technologies
%% Legacy PV
%%%Only need to add variables if new PV is not considered
if isempty(pv_legacy) == 0 && sum(pv_legacy(2,:)) > 0 &&  isempty(pv_v)
    
    if island == 0 && export_on == 1 %If grid tied, then include NEM and wholesale export
        %%% Variables that exist when grid tied
        var_pv.pv_nem = [];
        var_pv.pv_nem = sdpvar(T,1,'full'); %%% PV Production exported w/ NEM

            %%%Utility rates for building k
            index=find(ismember(rate_labels,rate(1)));
            
            %%%Adding values to the cost function
            Objective = Objective...
                + sum(sum(-day_multi.*export_price(:,index).*var_pv.pv_nem)); %%%NEM Revenue Cost
        
    else
        var_pv.pv_nem = [];
    end
    
    %%%PV Generation to meet building demand (kWh)
    var_pv.pv_elec = [];
    var_pv.pv_elec = sdpvar(T,1,'full'); %%% PV Production sent to the building
    
%     if ~iesmpty(el_v)
%         var_pv.pv_h2 = sdpvar(T,1,'full'); %%% PV Production sent to the building
%     end
    
    
    %%%Operating Costs
    Objective=Objective ...
        + pv_legacy(1,1)*(sum(sum(day_multi.*(var_pv.pv_elec + var_pv.pv_nem))));
    
elseif isempty(pv_legacy) == 1
    %%%If Legacy PV does not exist, then make the existing pv value zero
    pv_legacy = zeros(2,1);
end

%% Legacy generator
if ~isempty(dg_legacy)
    %%%DG Electrical Output
    var_ldg.ldg_elec = sdpvar(T,size(dg_legacy,2),'full');
    %%%DG Fuel Input
    var_ldg.ldg_fuel = sdpvar(T,size(dg_legacy,2),'full');
    %%%DG Fuel Input
    var_ldg.ldg_rfuel = sdpvar(T,size(dg_legacy,2),'full');
    %%%DG On/Off State - Number of variables is equal to:
    %%% (Time Instances) / On/Off length
    %     (dg_legacy(end,i)/t_step)
    %     ldg_off=binvar(ceil(length(time)/(dg_legacy(end,i)/t_step)),K,'full');
    
    %%%If hydrogen production is an option
    if ~isempty(el_v)
      var_ldg.ldg_hfuel = sdpvar(T,size(dg_legacy,2),'full');
    else
        var_ldg.ldg_hfuel = zeros(T,1);
    end
    
    for ii = 1:size(dg_legacy,2)
        Objective=Objective ...
            + sum(var_ldg.ldg_elec(:,ii))*dg_legacy(1,ii) ...
            + sum(var_ldg.ldg_fuel(:,ii))*ng_cost ...
            + sum(var_ldg.ldg_rfuel(:,ii))*rng_cost;
    end
else
    var_ldg.ldg_elec = zeros(T,1);
        var_ldg.ldg_hfuel = zeros(T,1);
    var_ldg.ldg_fuel = [];
    var_ldg.ldg_off = [];
    
end
%% Legacy bottoming systems
%%%Bottoming generator is any electricity producing device that operates
%%%based on heat recovered from another generator

if ~isempty(bot_legacy)
    %%%Bottom electrical output
    var_lbot.lbot_elec = sdpvar(length(elec),size(bot_legacy,2),'full');
    %%%Bottom operational state
    var_lbot.lbot_on = binvar(length(elec),size(bot_legacy,2),'full');
    
    %%%Bottoming cycle
    for i=1:size(bot_legacy,2)
        Objective=Objective+var_lbot.lbot_elec(:,1)'*(bot_legacy(1,i)*ones(length(time),1));%%%Bottoming cycle O&M
    end
else
    var_lbot.lbot_elec = zeros(T,1);
    var_lbot.lbot_on = zeros(T,1);
end
%% Legacy Heat recovery
if ~isempty(dg_legacy) && ~isempty(hr_legacy)
    %%%Heat recovery output
    var_ldg.hr_heat=sdpvar(length(elec),size(hr_legacy,2),'full');
    
    %%%If duct burner or HR heating source is available
    if ~isempty(db_legacy)
        %%%Duct burner - Conventional
        var_ldg.db_fire=sdpvar(length(elec),size(db_legacy,2),'full');
        %%%Duct burner - Renewable
        var_ldg.db_rfire=sdpvar(length(elec),size(db_legacy,2),'full');
        
        %%%If hydrogen production is an option
        if ~isempty(el_v)
            var_ldg.db_hfire = sdpvar(T,size(dg_legacy,2),'full');
        else
            var_ldg.db_hfire = zeros(T,1);
        end
                
        for ii = 1:size(db_legacy,2)
            %%%Duct burner and renewable duct burner
            Objective=Objective ...
                + var_ldg.db_fire'*((db(1,ii)+ng_cost)*ones(length(time),1)) ...
                + var_ldg.db_rfire'*((db(1,ii)+rng_cost)*ones(length(time),1)) ...
                + var_ldg.db_hfire'*((db(1,ii)+rng_cost)*ones(length(time),1));
        end
    else
        var_ldg.db_fire = [];
        var_ldg.db_rfire = [];
        var_ldg.db_hfire = [];
    end
    
else
    var_ldg.hr_heat = zeros(T,1);
    var_ldg.db_fire = zeros(T,1);
    var_ldg.db_rfire = zeros(T,1);
        var_ldg.db_hfire = [];
end
%% Legacy boiler
if ~isempty(boil_legacy)
    %%%Basic boiler
    var_boil.boil_fuel = sdpvar(length(elec),size(boil_legacy,2),'full');
    var_boil.boil_rfuel = sdpvar(length(elec),size(boil_legacy,2),'full');
    
    %%%If hydrogen production is an option
    if ~isempty(el_v)
        var_boil.boil_hfuel = sdpvar(T,size(dg_legacy,2),'full');
    else
        var_boil.boil_hfuel = zeros(T,1);
    end
    
    Objective=Objective ...
        +  sum(var_boil.boil_fuel)*(boil_legacy(1) + ng_cost) ...
        +sum(var_boil.boil_rfuel)*(boil_legacy(1) + rng_cost)...
        +sum(var_boil.boil_hfuel)*(boil_legacy(1) + rng_cost);
else
    var_boil.boil_fuel = zeros(T,1);
    var_boil.boil_rfuel = zeros(T,1);
    var_boil.boil_hfuel = zeros(T,1);
end

%% Legacy Generic Chiller
if ~isempty(cool) && sum(cool) > 0  && isempty(vc_legacy)
    var_vc.generic_cool = sdpvar(length(elec),size(boil_legacy,2),'full');
else
    var_vc.generic_cool = zeros(T,1);
end

%% Legacy Cold TES
if ~isempty(cool) && sum(cool) >0 && ~isempty(tes_legacy)
    %%%TES Energy Storage Vector
    %%%TES State of Charge
    var_ltes.ltes_soc = sdpvar(length(elec),size(tes_legacy,2),'full');
    %%%TES charging/discharging
    var_ltes.ltes_chrg = sdpvar(length(elec),size(tes_legacy,2),'full');
    var_ltes.ltes_dchrg = sdpvar(length(elec),size(tes_legacy,2),'full');
    
    %%%TES
    for i=1:size(tes_legacy,2)
        Objective=Objective + var_ltes.ltes_chrg(:,i)'*(tes_legacy(2,i)*ones(length(time),1))...
            + var_ltes.ltes_dchrg(:,i)'*(tes_legacy(3,i)*ones(length(time),1));
    end
    
else
    var_ltes.ltes_soc = zeros(T,1);
    var_ltes.ltes_chrg = zeros(T,1);
    var_ltes.ltes_dchrg = zeros(T,1);
end

%% Legacy Chillers
onoff_model = 1;

if ~isempty(cool) && sum(cool) >0 && ~isempty(vc_legacy)
     %%%Operational windows
    vc_hour_num = ceil(length(time)/4);
   
    
    
    if onoff_model
   
        vc_size = zeros(length(elec),size(vc_legacy,2));
        vc_cop=ones(length(elec),size(vc_legacy,2));
        for i=1:length(elec)
            vc_cop(i,:)=vc_cop(i,:).*(1./vc_legacy(2,:));
            vc_size(i,:) = vc_legacy(3,:);
        end
        
        
    %%%VC Cooling output
    var_lvc.lvc_cool = sdpvar(length(elec),size(vc_legacy,2),'full');
    %%%VC Operational State
    var_lvc.lvc_op = binvar(vc_hour_num,size(vc_legacy,2),'full');

    %%%VC Start
%     vc_start=binvar(vc_hour_num,size(vc_legacy,2),'full');
    
    %%%Electric Vapor Compression
    for i=1:size(vc_legacy,2)
        Objective = Objective ...
            + var_lvc.lvc_cool(:,i)'*(vc_legacy(1,i)*ones(length(time),1));
        %             + var_lvc.lvc_cool(:,i)'*(vc_legacy(1,i)*ones(length(time),1)); ...
        %                     + 10*sum(sum(vc_start));
    end
    
    
    
    else
        %%%VC Operational State
        vc_size = vc_legacy(3,:)/e_adjust;
        vc_cop = (1./vc_legacy(2,:));
    var_lvc.lvc_op = binvar(vc_hour_num,size(vc_legacy,2),'full');
        
    end
    
else
    var_lvc.lvc_op = 0;
    var_lvc.lvc_cool = zeros(T,1);
    vc_cop = 0;
end