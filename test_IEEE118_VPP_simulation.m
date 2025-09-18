%% 测试IEEE 118节点VPP协同调度仿真
% 验证修正后的代码是否正常工作

function test_IEEE118_VPP_simulation()
    
    fprintf('=== 开始测试IEEE 118节点VPP协同调度仿真 ===\n');
    
    try
        % 测试主函数
        fprintf('1. 测试主函数调用...\n');
        main_IEEE118_VPP_scheduling_corrected();
        fprintf('   主函数测试通过\n');
        
    catch ME
        fprintf('   测试失败: %s\n', ME.message);
        fprintf('   错误位置: %s (第%d行)\n', ME.stack(1).file, ME.stack(1).line);
        
        % 显示详细错误信息
        fprintf('   详细错误信息:\n');
        for i = 1:length(ME.stack)
            fprintf('     %s (第%d行)\n', ME.stack(i).file, ME.stack(i).line);
        end
    end
    
    fprintf('\n=== IEEE 118节点VPP仿真测试完成 ===\n');
    
end

%% 单独测试各个函数模块
function test_individual_functions()
    
    fprintf('=== 测试各个函数模块 ===\n');
    
    try
        %% 测试数据加载
        fprintf('1. 测试数据加载函数...\n');
        [bus_data, gen_data, branch_data, load_data] = load_IEEE118_data();
        fprintf('   数据加载成功: 母线%d个, 发电机%d台\n', size(bus_data,1), size(gen_data,1));
        
        %% 测试VPP子网络构建
        fprintf('2. 测试VPP子网络构建...\n');
        [VPP_data, num_VPPs] = build_VPP_subnetworks_corrected(bus_data, gen_data, load_data);
        fprintf('   VPP子网络构建成功: %d个VPP\n', num_VPPs);
        
        %% 测试成本计算
        fprintf('3. 测试成本计算函数...\n');
        test_gen_output = rand(size(gen_data, 1), 1) * 50 + 10; % 随机发电出力
        total_cost = calculate_total_VPP_cost(VPP_data, test_gen_output);
        fprintf('   成本计算成功: 总成本 $%.2f\n', total_cost);
        
        %% 测试QGA算法
        fprintf('4. 测试量子遗传算法...\n');
        lambda_test = ones(size(bus_data, 1), 1) * 25;
        solution = solve_VPP_subproblem_QGA(VPP_data{1}, lambda_test, 1);
        fprintf('   QGA算法测试成功: VPP1成本 $%.2f\n', solution.cost);
        
        fprintf('所有函数模块测试通过!\n');
        
    catch ME
        fprintf('函数模块测试失败: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf('错误位置: %s (第%d行)\n', ME.stack(1).file, ME.stack(1).line);
        end
    end
    
end