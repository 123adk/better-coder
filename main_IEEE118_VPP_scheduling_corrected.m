%% IEEE 118节点VPP协同调度仿真代码修正版
% 修正问题：
% 1. 移除不存在的文件依赖
% 2. 修正VPP子网络构建函数
% 3. 改进拉格朗日对偶算法的收敛性
% 4. 修正成本计算

function main_IEEE118_VPP_scheduling_corrected()
    
    clc; clear; close all;
    
    fprintf('=== IEEE 118节点VPP协同调度仿真开始 ===\n');
    
    %% 1. 初始化和数据加载
    try
        % 启动并行计算池（移除不存在的文件依赖）
        if isempty(gcp('nocreate'))
            parpool('local', 4); % 使用4个工作进程
            fprintf('并行计算池启动成功\n');
        end
    catch ME
        fprintf('并行计算池启动失败，使用串行计算: %s\n', ME.message);
    end
    
    % 加载IEEE 118节点系统数据
    [bus_data, gen_data, branch_data, load_data] = load_IEEE118_data();
    
    % 24小时负荷预测数据（标幺值）
    load_forecast = [0.52, 0.48, 0.46, 0.44, 0.43, 0.45, 0.52, 0.65, ...
                     0.78, 0.85, 0.88, 0.90, 0.92, 0.90, 0.88, 0.87, ...
                     0.89, 0.93, 0.96, 0.95, 0.90, 0.80, 0.70, 0.58];
    
    fprintf('IEEE 118节点系统数据加载完成\n');
    fprintf('总母线数: %d, 发电机数: %d, 支路数: %d\n', ...
        size(bus_data,1), size(gen_data,1), size(branch_data,1));
    
    %% 2. VPP子网络构建（修正发电机组识别错误）
    fprintf('\n=== 构建VPP子网络 ===\n');
    [VPP_data, num_VPPs] = build_VPP_subnetworks_corrected(bus_data, gen_data, load_data);
    
    % 显示各VPP的机组数
    for i = 1:num_VPPs
        fprintf('VPP %d: 发电机组数 = %d, 负荷节点数 = %d\n', ...
            i, length(VPP_data{i}.gen_indices), length(VPP_data{i}.load_indices));
    end
    
    %% 3. 24小时调度优化
    fprintf('\n=== 开始24小时调度优化 ===\n');
    
    % 初始化结果存储
    scheduling_results = cell(24, 1);
    total_costs = zeros(24, 1);
    
    % 拉格朗日乘子初始化（修正初始值选取）
    lambda_init = ones(size(bus_data, 1), 1) * 30; % 初始电价30$/MWh
    lambda_history = zeros(24, size(bus_data, 1));
    
    for hour = 1:24
        fprintf('\n--- 第%d小时调度优化 ---\n', hour);
        
        % 当前小时负荷
        current_load = load_data * load_forecast(hour);
        
        % 拉格朗日对偶分解优化（改进收敛性）
        [gen_output, lambda_final, convergence_info] = ...
            lagrangian_dual_optimization_improved(VPP_data, current_load, lambda_init, hour);
        
        % 计算总成本
        total_cost = calculate_total_VPP_cost(VPP_data, gen_output);
        
        % 存储结果
        scheduling_results{hour} = struct('gen_output', gen_output, ...
                                        'lambda', lambda_final, ...
                                        'total_cost', total_cost, ...
                                        'convergence', convergence_info);
        total_costs(hour) = total_cost;
        lambda_history(hour, :) = lambda_final';
        
        % 更新下一小时的拉格朗日乘子初始值
        lambda_init = lambda_final;
        
        fprintf('第%d小时优化完成，总成本: $%.2f, 收敛迭代数: %d\n', ...
            hour, total_cost, convergence_info.iterations);
    end
    
    %% 4. 结果分析和可视化
    fprintf('\n=== 生成结果分析 ===\n');
    generate_results_analysis(scheduling_results, total_costs, lambda_history, VPP_data);
    
    % 关闭并行计算池
    try
        delete(gcp('nocreate'));
        fprintf('并行计算池已关闭\n');
    catch
        % 忽略关闭错误
    end
    
    fprintf('\n=== IEEE 118节点VPP协同调度仿真完成 ===\n');
    fprintf('24小时总成本: $%.2f\n', sum(total_costs));
    
end

%% 子函数：加载IEEE 118节点系统数据
function [bus_data, gen_data, branch_data, load_data] = load_IEEE118_data()
    
    % IEEE 118节点母线数据 [母线号, 类型, 电压幅值, 相角, 有功负荷, 无功负荷, ...]
    % 这里使用简化的数据结构，实际应用中需要完整的IEEE 118节点数据
    bus_data = [(1:118)', ones(118,1), ones(118,1), zeros(118,1), ...
                rand(118,1)*100, rand(118,1)*50, zeros(118,6)]; % 简化数据
    
    % 发电机数据包含VPP_ID（第13列）
    % [母线号, Pg, Qg, Qmax, Qmin, Vg, mBase, status, Pmax, Pmin, Pc1, Pc2, VPP_ID, ...]
    gen_data = [
        % VPP 1的发电机
        1,  50,  0, 100, -100, 1.0, 100, 1, 100,  10, 0.02, 0.001, 1, 25, 1.2;
        2,  40,  0,  80,  -80, 1.0, 100, 1,  80,   8, 0.03, 0.002, 1, 20, 1.1;
        3,  30,  0,  60,  -60, 1.0, 100, 1,  60,   6, 0.04, 0.003, 1, 15, 1.0;
        % VPP 2的发电机
        10, 70,  0, 120, -120, 1.0, 100, 1, 120,  12, 0.025, 0.0015, 2, 30, 1.3;
        12, 60,  0, 100, -100, 1.0, 100, 1, 100,  10, 0.035, 0.0025, 2, 25, 1.2;
        % VPP 3的发电机
        25, 80,  0, 140, -140, 1.0, 100, 1, 140,  14, 0.02, 0.001, 3, 35, 1.4;
        26, 50,  0,  90,  -90, 1.0, 100, 1,  90,   9, 0.03, 0.002, 3, 22, 1.1;
        27, 40,  0,  70,  -70, 1.0, 100, 1,  70,   7, 0.04, 0.003, 3, 18, 1.0;
        % 添加更多发电机以确保每个VPP都有机组
        49, 45,  0,  85,  -85, 1.0, 100, 1,  85,   8, 0.032, 0.0022, 4, 21, 1.1;
        54, 55,  0,  95,  -95, 1.0, 100, 1,  95,   9, 0.028, 0.0018, 4, 27, 1.2;
        59, 35,  0,  65,  -65, 1.0, 100, 1,  65,   6, 0.038, 0.0028, 5, 17, 1.0;
        61, 65,  0, 110, -110, 1.0, 100, 1, 110,  11, 0.024, 0.0016, 5, 32, 1.3
    ];
    
    % 支路数据（简化）
    branch_data = [
        1,  2, 0.0303, 0.0999, 0.0254, 250, 250, 0, 0, 0, 1, -360, 360;
        1,  3, 0.0129, 0.0424, 0.0108, 250, 250, 0, 0, 0, 1, -360, 360;
        % ... 添加更多支路数据
    ];
    
    % 负荷数据（基准负荷）
    load_data = bus_data(:, 5); % 有功负荷列
    
end

%% 子函数：构建VPP子网络（修正版）
function [VPP_data, num_VPPs] = build_VPP_subnetworks_corrected(bus_data, gen_data, load_data)
    
    % 从发电机数据的第13列获取VPP_ID
    VPP_IDs = gen_data(:, 13);
    num_VPPs = max(VPP_IDs);
    
    fprintf('检测到 %d 个VPP\n', num_VPPs);
    
    VPP_data = cell(num_VPPs, 1);
    
    for vpp_id = 1:num_VPPs
        % 找到属于当前VPP的发电机
        gen_mask = (VPP_IDs == vpp_id);
        vpp_gen_indices = find(gen_mask);
        vpp_gen_buses = gen_data(gen_mask, 1); % 发电机所在母线
        
        % 为每个VPP分配负荷节点（简化分配策略）
        load_per_vpp = ceil(length(load_data) / num_VPPs);
        start_idx = (vpp_id - 1) * load_per_vpp + 1;
        end_idx = min(vpp_id * load_per_vpp, length(load_data));
        vpp_load_indices = start_idx:end_idx;
        
        % 构建VPP数据结构
        VPP_data{vpp_id} = struct();
        VPP_data{vpp_id}.vpp_id = vpp_id;
        VPP_data{vpp_id}.gen_indices = vpp_gen_indices;
        VPP_data{vpp_id}.gen_buses = vpp_gen_buses;
        VPP_data{vpp_id}.load_indices = vpp_load_indices;
        VPP_data{vpp_id}.gen_data = gen_data(gen_mask, :);
        VPP_data{vpp_id}.load_data = load_data(vpp_load_indices);
        
        % 添加可中断负荷（负值成本）
        VPP_data{vpp_id}.interruptible_load = sum(load_data(vpp_load_indices)) * 0.1; % 10%可中断
        VPP_data{vpp_id}.interruption_cost = -50; % 负值成本 $/MWh
    end
    
end