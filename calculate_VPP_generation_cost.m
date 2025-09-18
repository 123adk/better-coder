%% VPP发电成本计算函数
% 正确处理可中断负荷的负值成本

function total_cost = calculate_VPP_generation_cost(P, gen_data)
    
    % 发电机成本参数
    % gen_data列索引：[母线号, Pg, Qg, Qmax, Qmin, Vg, mBase, status, Pmax, Pmin, Pc1, Pc2, VPP_ID, cost_a, cost_b]
    
    num_gens = length(P);
    total_cost = 0;
    
    for i = 1:num_gens
        
        % 提取成本系数
        if size(gen_data, 2) >= 15
            cost_a = gen_data(i, 14);  % 二次项系数 $/MW²h
            cost_b = gen_data(i, 15);  % 一次项系数 $/MWh
            cost_c = 0;                % 常数项，默认为0
        else
            % 默认成本系数
            cost_a = 0.02;
            cost_b = 25;
            cost_c = 0;
        end
        
        % 发电出力
        Pi = P(i);
        
        % 二次成本函数：Cost = a*P² + b*P + c
        gen_cost_i = cost_a * Pi^2 + cost_b * Pi + cost_c;
        
        % 确保成本非负
        gen_cost_i = max(gen_cost_i, 0);
        
        total_cost = total_cost + gen_cost_i;
    end
    
end

%% 计算总VPP成本（包括可中断负荷）
function total_cost = calculate_total_VPP_cost(VPP_data, gen_output)
    
    total_cost = 0;
    gen_idx = 1;
    
    for vpp = 1:length(VPP_data)
        
        vpp_data = VPP_data{vpp};
        num_gens = length(vpp_data.gen_indices);
        
        % 当前VPP的发电出力
        vpp_gen_output = gen_output(gen_idx:gen_idx+num_gens-1);
        
        % 发电成本
        gen_cost = calculate_VPP_generation_cost(vpp_gen_output, vpp_data.gen_data);
        
        % 可中断负荷成本（负值成本）
        interruptible_cost = 0;
        if isfield(vpp_data, 'interruptible_load') && isfield(vpp_data, 'interruption_cost')
            % 简化：假设在高电价时段中断10%的负荷
            interruptible_amount = vpp_data.interruptible_load * 0.1;
            interruptible_cost = interruptible_amount * vpp_data.interruption_cost; % 负值
        end
        
        vpp_total_cost = gen_cost + interruptible_cost;
        total_cost = total_cost + vpp_total_cost;
        
        gen_idx = gen_idx + num_gens;
    end
    
end

%% 计算VPP运行成本明细
function cost_details = calculate_VPP_cost_details(VPP_data, gen_output, lambda)
    
    num_VPPs = length(VPP_data);
    cost_details = struct();
    cost_details.vpp_costs = zeros(num_VPPs, 1);
    cost_details.gen_costs = zeros(num_VPPs, 1);
    cost_details.interruptible_costs = zeros(num_VPPs, 1);
    cost_details.revenue = zeros(num_VPPs, 1);
    cost_details.profit = zeros(num_VPPs, 1);
    
    gen_idx = 1;
    
    for vpp = 1:num_VPPs
        
        vpp_data = VPP_data{vpp};
        num_gens = length(vpp_data.gen_indices);
        gen_buses = vpp_data.gen_buses;
        
        % 当前VPP的发电出力
        vpp_gen_output = gen_output(gen_idx:gen_idx+num_gens-1);
        
        % 发电成本
        gen_cost = calculate_VPP_generation_cost(vpp_gen_output, vpp_data.gen_data);
        cost_details.gen_costs(vpp) = gen_cost;
        
        % 可中断负荷成本
        interruptible_cost = 0;
        if isfield(vpp_data, 'interruptible_load') && isfield(vpp_data, 'interruption_cost')
            interruptible_amount = vpp_data.interruptible_load * 0.1;
            interruptible_cost = interruptible_amount * vpp_data.interruption_cost;
        end
        cost_details.interruptible_costs(vpp) = interruptible_cost;
        
        % 总成本
        cost_details.vpp_costs(vpp) = gen_cost + interruptible_cost;
        
        % 收入（根据拉格朗日乘子计算）
        revenue = 0;
        for i = 1:num_gens
            bus_idx = gen_buses(i);
            if bus_idx <= length(lambda)
                revenue = revenue + lambda(bus_idx) * vpp_gen_output(i);
            end
        end
        cost_details.revenue(vpp) = revenue;
        
        % 利润
        cost_details.profit(vpp) = revenue - cost_details.vpp_costs(vpp);
        
        gen_idx = gen_idx + num_gens;
    end
    
    % 系统总成本
    cost_details.total_cost = sum(cost_details.vpp_costs);
    cost_details.total_revenue = sum(cost_details.revenue);
    cost_details.total_profit = sum(cost_details.profit);
    
end