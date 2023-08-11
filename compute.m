function [inputs] = compute(i,inputs)
 global outputs
    
    %% Kite mass 
    if inputs.massOverride == 1
      outputs.m_kite(i) = inputs.kiteMass;
    else
      %Vincent Bonnin's simple mass model developed at Ampyx Power. Based on AP3 data and projected data for larger systems (AP4-AP5)      
      a1     = 0.002415;       a2     = 0.0090239;       b1     = 0.17025;       b2     = 3.2493;
      k1     = 5;              c1     = 0.46608;         d1     = 0.65962;       k2     = 1.1935;
      AR_ref = 12;
      a = a1*(inputs.Tmax/inputs.WA) + a2;
      b = b1*(inputs.Tmax/inputs.WA) + b2;
      outputs.m_kite(i) = 10*(a*inputs.WA^2 +b*inputs.WA-k1)*(c1*(inputs.AR/AR_ref)^2-d1*(inputs.AR/AR_ref)+k2); 
    end
    
    %% Tether length and height calculations based on variable values
    outputs.wingSpan           = sqrt(inputs.AR*inputs.WA);     
    outputs.L_teMin(i)         = outputs.startPattRadius(i)/sin(outputs.pattAngRadius(i));
    outputs.pattStartGrClr(i)  = outputs.L_teMin(i)*sin(outputs.avgPattEle(i)-outputs.pattAngRadius(i));
    outputs.H_cycleStart(i)    = outputs.L_teMin(i)*cos(outputs.pattAngRadius(i))*sin(outputs.avgPattEle(i));
    outputs.L_teMax(i)         = outputs.L_teMin(i)+outputs.deltaL(i)/cos(outputs.pattAngRadius(i)); 
    outputs.pattEndGrClr(i)    = outputs.L_teMax(i)*sin(outputs.avgPattEle(i)-outputs.pattAngRadius(i));
    outputs.L_teAvg(i)         = (outputs.L_teMax(i)+outputs.L_teMin(i))/2; %[m]
    outputs.H_cycleAvg(i)      = outputs.L_teAvg(i)*cos(outputs.pattAngRadius(i))*sin(outputs.avgPattEle(i));
    outputs.H_cycleEnd(i)      = outputs.L_teMax(i)*cos(outputs.pattAngRadius(i))*sin(outputs.avgPattEle(i));
    outputs.D_te               = sqrt(inputs.Tmax*1000/inputs.Te_matStrength*4/pi()); %[m] safety factor could be added (say *1.1)
    
    %% Effective mass (Kite + tether)
    outputs.m_te(i)  = inputs.Te_matDensity*pi()/4*outputs.D_te^2*outputs.L_teAvg(i)*inputs.F_TeCurve; % Could add (say 0.85) as safety factor on material density
    outputs.m_eff(i) = outputs.m_kite(i)+sin(outputs.avgPattEle(i))*outputs.m_te(i);

    %% W
    outputs.W(i)     = outputs.m_eff(i)*inputs.gravity;
    
    %% Cycle avg. mech reel-out power considering vertical wind shear
     
    % Discretizing the reel-out length in chosen number of elements
    % Found to be not highly sensitive to the number of elements
     outputs.deltaLelems   = inputs.numDeltaLelems; 
     outputs.elemDeltaL(i) = outputs.deltaL(i)/outputs.deltaLelems;
  
     % Assigning and evaluating a single flight state equilibrium for each
     % length element considering top point of the pattern
     for j = 1:outputs.deltaLelems
      
        % For vector in further sections
        outputs.W(i,j) = outputs.W(i);
        % Effective CD
        outputs.CD_kite(i,j)   = inputs.CD0 + (outputs.CL(i,j)-inputs.CL0_airfoil)^2/(pi()*inputs.AR*inputs.e);
        outputs.CD_tether(i)   = (1/4)*inputs.CD_te*outputs.D_te*outputs.L_teAvg(i)*inputs.F_TeCurve/inputs.WA;
        outputs.CD(i,j)        = outputs.CD_kite(i,j) + outputs.CD_tether(i);

        % Pattern average height
        if j == 1
          outputs.h_inCycle(i,j) = outputs.H_cycleStart(i) + outputs.elemDeltaL(i)/2*sin(outputs.avgPattEle(i));
        else
          outputs.h_inCycle(i,j) = outputs.h_inCycle(i,j-1) + outputs.elemDeltaL(i)*sin(outputs.avgPattEle(i));
        end
        
        % Pattern radius at point of interest on deltaL
        if j == 1
          outputs.pattRadius(i,j) = (outputs.startPattRadius(i) + (outputs.elemDeltaL(i)*tan(outputs.pattAngRadius(i)) + outputs.startPattRadius(i)))/2;
        else
          outputs.pattRadius(i,j) = (outputs.pattRadius(i,j-1) + (j*outputs.elemDeltaL(i)*tan(outputs.pattAngRadius(i)) + outputs.startPattRadius(i)))/2;
        end
        
        % Wind speed at top pattern point                          
        outputs.Vw_top(i,j) = inputs.vw_ref(i)*((outputs.h_inCycle(i,j)+outputs.pattRadius(i,j)*cos(outputs.avgPattEle(i)))...
                            /inputs.h_ref)^inputs.windShearExp;
        
        % Air density as a function of height   % Ref: https://en.wikipedia.org/wiki/Density_of_air
        M = 0.0289644; % [kg/mol]
        R = 8.3144598; % [N·m/(mol·K)]
        T = 288.15;    % [Kelvin]
        L = 0.0065;    % [Kelvin/m] 
        outputs.rho_air(i,j) = inputs.airDensity*(1-L*(outputs.h_inCycle(i,j)+outputs.pattRadius(i,j)*cos(outputs.avgPattEle(i)))/T)^(inputs.gravity*M/R/L-1); 
        
        % Intermediate calculation for brevity
        outputs.CR(i,j)       = sqrt(outputs.CL(i,j)^2+outputs.CD(i,j)^2);
        outputs.halfRhoS(i,j) = 0.5*outputs.rho_air(i,j)*inputs.WA;
        
        
%          No effects: Top point of the pattern

        % apparent wind velocity magnitude
        outputs.Va_top(i,j) = outputs.Vw_top(i,j)*(cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.reelOutF(i,j))*...
                              sqrt(1+outputs.kRatio(i,j)^2);
        % aerodynamic force magnitude
        outputs.Fa_top(i,j) = outputs.halfRhoS(i,j)*outputs.CR(i,j)*outputs.Va_top(i,j)^2;
        
        % tangential kite velocity factor
        outputs.lambda(i,j) = sqrt(cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))^2 + outputs.kRatio(i,j)^2*...
                                (cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))^2-outputs.reelOutF(i,j))-1);
        
        % magnitude of centripetal force
        outputs.Fc(i,j) = outputs.m_eff(i)*(outputs.lambda(i,j)*outputs.Vw_top(i,j))^2/outputs.pattRadius(i,j);
        
        outputs.Fc(i,j) = 0;
        
        % gravitational force vector
        outputs.Fg_r(i,j) = -outputs.W(i,j)*sin(outputs.avgPattEle(i)+outputs.pattAngRadius(i))+outputs.Fc(i,j)*sin(outputs.pattAngRadius(i));
        outputs.Fg_p(i,j) = outputs.W(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.Fc(i,j)*cos(outputs.pattAngRadius(i));
        outputs.Fg_z(i,j) = 0;
        
        % aerodynamic force vector
        outputs.Fa_p(i,j) = -outputs.Fg_p(i,j);
        outputs.Fa_r(i,j) = sqrt(outputs.Fa_top(i,j)^2-outputs.Fa_p(i,j)^2);
        outputs.Fa_z(i,j) = 0;
        
        % apparent wind velocity vector
        outputs.va_r(i,j) = outputs.Vw_top(i,j)*(cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.reelOutF(i,j));
        outputs.va_p(i,j) = outputs.Vw_top(i,j)*sin(outputs.avgPattEle(i)+outputs.pattAngRadius(i));
        outputs.va_z(i,j) = -outputs.lambda(i,j)*outputs.Vw_top(i,j);
        
        % dot product F_a*v_a;
        outputs.F_dot_v(i,j) = (outputs.Fa_r(i,j)*outputs.va_r(i,j) + outputs.Fa_p(i,j)*outputs.va_p(i,j) + outputs.Fa_z(i,j)*outputs.va_z(i,j));
        
        % drag vector
        outputs.D_r(i,j) = (outputs.F_dot_v(i,j)/outputs.Va_top(i,j)^2)*outputs.va_r(i,j);
        outputs.D_p(i,j) = (outputs.F_dot_v(i,j)/outputs.Va_top(i,j)^2)*outputs.va_p(i,j);
        outputs.D_z(i,j) = (outputs.F_dot_v(i,j)/outputs.Va_top(i,j)^2)*outputs.va_z(i,j);
        
        % lift vector
        outputs.L_r(i,j) = outputs.Fa_r(i,j) - outputs.D_r(i,j);
        outputs.L_p(i,j) = outputs.Fa_p(i,j) - outputs.D_p(i,j);
        outputs.L_z(i,j) = outputs.Fa_z(i,j) - outputs.D_z(i,j);
        
        % drag magnitude
        outputs.D(i,j) = sqrt(outputs.D_r(i,j)^2 + outputs.D_p(i,j)^2 + outputs.D_z(i,j)^2);
        
        % lift magnitude
        outputs.L(i,j) = sqrt(outputs.L_r(i,j)^2 + outputs.L_p(i,j)^2 + outputs.L_z(i,j)^2);
        
        outputs.T_top(i,j) = outputs.Fa_r(i,j) + outputs.Fg_r(i,j);
        
        outputs.VRO_top(i,j) = outputs.reelOutF(i,j)*outputs.Vw_top(i,j);
        
        % lift-to-drag ratio that follows from the chosen kinematic ratio
        outputs.k_result(i,j) = sqrt(((outputs.Fa_top(i,j)*outputs.Va_top(i,j))/outputs.F_dot_v(i,j))^2-1);
        
        %% Updating variable names for brevity in the following sections
        outputs.VRO(i,j)  = outputs.VRO_top(i,j);
        outputs.T(i,j)    = outputs.T_top(i,j);
        outputs.VC(i,j)   = outputs.lambda(i,j)*outputs.Vw_top(i,j);
         
        % Effective mechanical reel-out power
        outputs.PROeff_mech(i,j) = outputs.T(i,j)*outputs.VRO(i,j); %[W]
       
        % Effective electrical reel-out power
        % Generator efficiency. As a function of RPM/RPM_max, where RPM_max is driven by winch i.e Max VRI
        outputs.genEff_RO(i,j)  = (inputs.etaGen.param(1)*(outputs.VRO(i,j)/inputs.etaGen.Vmax)^3 + ...
                                      inputs.etaGen.param(2)*(outputs.VRO(i,j)/inputs.etaGen.Vmax)^2 + ...
                                        inputs.etaGen.param(3)*(outputs.VRO(i,j)/inputs.etaGen.Vmax)+inputs.etaGen.param(4))^sign(1);
        outputs.PROeff_elec(i,j) = outputs.PROeff_mech(i,j)*inputs.etaGearbox*outputs.genEff_RO(i,j)*inputs.etaPE;

        % Effective mechanical reel-in power
        outputs.VA_RI(i,j)       = sqrt(outputs.Vw_top(i,j)^2 +outputs.VRI(i)^2 +2*outputs.Vw_top(i,j)*outputs.VRI(i)*cos(outputs.avgPattEle(i)));
        outputs.CL_RI(i,j)       = 2*outputs.W(i)/(outputs.rho_air(i,j)*outputs.VA_RI(i,j)^2*inputs.WA);
        outputs.CD_RI(i,j)       = inputs.CD0+(outputs.CL_RI(i,j)- inputs.CL0_airfoil)^2/(pi()*inputs.AR*inputs.e) + outputs.CD_tether(i);
        outputs.PRIeff_mech(i,j) = 0.5*outputs.rho_air(i,j)*outputs.CD_RI(i,j)*inputs.WA*outputs.VA_RI(i,j)^3;

        % Generator efficiency during RI: As a function of RPM/RPM_max, where RPM_max is driven by winch i.e Max VRI
        outputs.genEff_RI(i) = (inputs.etaGen.param(1)*(outputs.VRI(i)/inputs.etaGen.Vmax)^3 + ...
                                 inputs.etaGen.param(2)*(outputs.VRI(i)/inputs.etaGen.Vmax)^2 + ...
                                  inputs.etaGen.param(3)*(outputs.VRI(i)/inputs.etaGen.Vmax)+inputs.etaGen.param(4))^sign(1);
        
        % Effective electrical reel-in power
        outputs.PRIeff_elec(i,j) = outputs.PRIeff_mech(i,j)/inputs.etaGearbox/inputs.etaSto/outputs.genEff_RI(i)/inputs.etaPE;

     end
         
    %% Cycle simulation
     
    % Reel-out time
     if outputs.VRO(i,:)<0
      outputs.t1(i)             = 0;
      outputs.tROeff(i,:)       = 0./outputs.VRO(i,:);
      outputs.tRO(i)            = 0;
     else
      outputs.t1(i)       = outputs.VRO(i,1)/inputs.maxAcc;
      outputs.tROeff(i,:) = outputs.elemDeltaL(i)./outputs.VRO(i,:);
      outputs.tRO(i)      = outputs.t1(i) + sum(outputs.tROeff(i,:));
     end
     
      % Reel-out power during transition
      outputs.PRO1_mech(i) = outputs.PROeff_mech(i,1)/2;
      outputs.PRO1_elec(i) = outputs.PROeff_elec(i,1)/2;

      % Reel-out power 
      if outputs.VRO(i,:)<0
        outputs.PRO_mech(i) = 1e-9;
      else
        outputs.PRO_mech(i) = (sum(outputs.PROeff_mech(i,:).*outputs.tROeff(i,:)) + outputs.PRO1_mech(i)*outputs.t1(i))/outputs.tRO(i);
        outputs.PRO_elec(i) = (sum(outputs.PROeff_elec(i,:).*outputs.tROeff(i,:)) + outputs.PRO1_elec(i)*outputs.t1(i))/outputs.tRO(i);
      end

      % Reel-in time
      if outputs.VRO(i,:)<0
        outputs.t2(i)             = 0;
        outputs.tRIeff(i,:)       = ones(1,outputs.deltaLelems).*0;
        outputs.tRI(i)            = 0;
      else
        outputs.t2(i)       = outputs.VRI(i)/inputs.maxAcc;
        outputs.tRIeff(i,:) = ones(1,outputs.deltaLelems).*outputs.elemDeltaL(i)/outputs.VRI(i);
        outputs.tRI(i)      = outputs.t2(i) + sum(outputs.tRIeff(i,:));
      end
      
      % Reel-in power duing transition
      outputs.PRI2_mech(i)     = outputs.PRIeff_mech(i,1)/2;
      outputs.PRI2_elec(i)     = outputs.PRIeff_elec(i,1)/2;

      % Reel-in power 
      outputs.PRI_mech(i) = (sum(outputs.PRIeff_mech(i,:).*outputs.tRIeff(i,:)) + outputs.PRI2_mech(i)*outputs.t2(i))/outputs.tRI(i);
      outputs.PRI_elec(i) = (sum(outputs.PRIeff_elec(i,:).*outputs.tRIeff(i,:)) + outputs.PRI2_elec(i)*outputs.t2(i))/outputs.tRI(i);

      % Cycle time
      outputs.tCycle(i) = outputs.tRO(i)+outputs.tRI(i);

      % Time for one pattern revolution and number of patterns in the cycle
      outputs.tPatt(i,:)     = 2*pi()*outputs.pattRadius(i,:)./outputs.VC(i,:);
      outputs.numOfPatt(i,:) = outputs.tRO(i)./outputs.tPatt(i,:);

      %% Electrical cycle power
      if outputs.VRO(i,:)<0
        outputs.P_cycleElec(i) = 0;
      else
       outputs.P_cycleElec(i) = (sum(outputs.tROeff(i,:).*outputs.PROeff_elec(i,:)) + outputs.t1(i)*outputs.PRO1_elec(i) - ...
                                   sum(outputs.tRIeff(i,:).*outputs.PRIeff_elec(i,:)) -outputs.t2(i)*outputs.PRI2_elec(i))/outputs.tCycle(i);    
      end

      % Mechanical cycle power - without drivetrain eff
      outputs.P_cycleMech(i) = (sum(outputs.tROeff(i,:).*outputs.PROeff_mech(i,:)) + outputs.t1(i)*outputs.PRO1_mech(i) - ...
                                   sum(outputs.tRIeff(i,:).*outputs.PRIeff_mech(i,:)) - outputs.t2(i)*outputs.PRI2_mech(i))/outputs.tCycle(i);

end      

 % No effects: Top point
% %         outputs.Va_top(i,j) = outputs.Vc_top(i,j)/sqrt(1-(outputs.CD(i,j)/outputs.CL(i,j))^2);
% %           outputs.Va_top(i,j) = outputs.Vc_top(i,j)*sqrt(1+(1/outputs.kRatio(i,j))^2);
% %           outputs.VSR_top(i,j) = outputs.Vw_top(i,j)*(cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.reelOutF(i,j));
%           
% %           outputs.Vc_top(i,j) = outputs.Va_top(i,j)*sqrt(1-(1/outputs.kRatio(i,j))^2);
%           outputs.Vc_top(i,j) = sqrt(outputs.Va_top(i,j).^2 - outputs.VSR_top(i,j).^2);
%           
%          % L, D and Fa 
%          outputs.Fa_top(i,j) = outputs.halfRhoS(i,j)*outputs.CR(i,j)*outputs.Va_top(i,j)^2;
%          
%          outputs.L_top(i,j) = outputs.halfRhoS(i,j)*outputs.CL(i,j)*outputs.Va_top(i,j)^2;
%          outputs.D_top(i,j) = outputs.halfRhoS(i,j)*outputs.CD(i,j)*outputs.Va_top(i,j)^2;
%         
%          
%         
%         % Tether force
%         outputs.T_top(i,j)   = outputs.Fa_top(i,j);     
%         
%         % Sink rate in tether tension direction
% %        outputs.VSR_top(i,j) = sqrt(outputs.Va_top(i,j).^2 - outputs.Vc_top(i,j).^2);
% %          outputs.VSR_top(i,j) = outputs.Vc_top(i,j)/outputs.kRatio(i,j);
%         outputs.VRO_top(i,j) = outputs.reelOutF(i,j)*outputs.Vw_top(i,j);
% %          outputs.VSR_top(i,j) = outputs.Vc_top(i,j)*(outputs.D_top(i,j)/outputs.L_top(i,j));
%        
%         % Reel-out speed
% %        outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.VSR_top(i,j);
%        
% %           outputs.reelOutF(i,j) = outputs.VRO_top(i,j)/outputs.Vw_top(i,j);
        

           
%         % All effects: Top point of the pattern
% 
%         % Centripetal force
%          outputs.Fc_top(i,j) = outputs.m_eff(i)*outputs.Vc_top(i,j)^2/outputs.pattRadius(i,j);
%         
%         % Airspeed
%         outputs.Va_top(i,j) = sqrt((outputs.W(i)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))+outputs.Fc_top(i,j)*cos(outputs.pattAngRadius(i)))/...
%                                (outputs.halfRhoS(i,j)*outputs.CR(i,j)*sin(outputs.rollAngleTop(i,j))));
% 
%          % Resultant Aero force
%         outputs.L_top(i,j) = outputs.halfRhoS(i,j)*outputs.CL(i,j)*outputs.Va_top(i,j)^2;
%         outputs.D_top(i,j) = outputs.halfRhoS(i,j)*outputs.CD(i,j)*outputs.Va_top(i,j)^2;
%         outputs.Fa_top(i,j) = outputs.halfRhoS(i,j)*outputs.CR(i,j)*outputs.Va_top(i,j)^2;
%         
%         % Tether force
%         outputs.T_top(i,j)   = outputs.Fa_top(i,j)*cos(outputs.rollAngleTop(i,j)) - ...
%                outputs.W(i)*sin(outputs.avgPattEle(i)+outputs.pattAngRadius(i))+outputs.Fc_top(i,j)*sin(outputs.pattAngRadius(i));
%           
%         % Sink rate considering high Lift to Drag ratio -> small glide angles
% %        outputs.VSR_top(i,j) = outputs.Vc_top(i,j)*(outputs.D_top(i,j)/outputs.L_top(i,j)*cos(outputs.rollAngleTop(i,j)));
%          outputs.VSR_top(i,j) = sqrt(outputs.Va_top(i,j).^2 - outputs.Vc_top(i,j).^2);
% 
% %           outputs.VSR_top(i,j) = sqrt(outputs.Va_top(i,j).^2 - (outputs.Vc_top(i,j)/cos(outputs.rollAngleTop(i,j))).^2);
% 
% %           outputs.vk_Fa(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))*cos(outputs.rollAngleTop(i,j))-outputs.VSR_top(i,j);        
% %           outputs.VRO_top(i,j) = outputs.vk_Fa(i,j)*cos(outputs.rollAngleTop(i,j));
% 
% %         outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i)) - outputs.VSR_top(i,j)*cos(outputs.rollAngleTop(i,j));
%         
%         % Reel-out speed, Sink rate in tether tension direction has to be used
%        outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.VSR_top(i,j);%*cos(outputs.rollAngleTop(i,j));
%        outputs.reelOutF(i,j) = outputs.VRO_top(i,j)/outputs.Vw_top(i,j);
     
      
       
        % All effects: Bottom point of the pattern
        
%         % Centripetal force
%          outputs.Fc_top(i,j) = outputs.m_eff(i)*outputs.Vc_top(i,j)^2/outputs.pattRadius(i,j);
%         
%         % Airspeed
%        outputs.Va_top(i,j) = sqrt((outputs.W(i)*cos(outputs.avgPattEle(i)-outputs.pattAngRadius(i))+outputs.Fc_top(i,j)*cos(outputs.pattAngRadius(i)))/...
%                                (outputs.halfRhoS(i,j)*outputs.CR(i,j)*sin(outputs.rollAngleTop(i,j))));
%                                                                   
%          % Resultant Aero force
%         outputs.Fa_top(i,j) = outputs.halfRhoS(i,j)*outputs.CR(i,j)*outputs.Va_top(i,j)^2;
%         
%         % Tether force
%         outputs.T_top(i,j)   = outputs.Fa_top(i,j)*cos(outputs.rollAngleTop(i,j)) - ...
%                outputs.W(i)*sin(outputs.avgPattEle(i)-outputs.pattAngRadius(i))+outputs.Fc_top(i,j)*sin(outputs.pattAngRadius(i));
%           
%         % Sink rate in tether tension direction
% %         outputs.VSR_top(i,j) = outputs.Va_top(i,j)*outputs.CD(i,j)/outputs.CL(i,j);
%          outputs.VSR_top(i,j) = sqrt(outputs.Va_top(i,j).^2 - outputs.Vc_top(i,j).^2);
%        
%         % Reel-out speed
%         outputs.v_k_r(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))*cos(outputs.rollAngleTop(i,j))-outputs.VSR_top(i,j);
%         outputs.VRO_top(i,j) = outputs.v_k_r(i,j)*cos(outputs.rollAngleTop(i,j));
% %         outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i)) - outputs.VSR_top(i,j)/cos(outputs.rollAngleTop(i,j));
%         
% %         outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)-outputs.pattAngRadius(i))-outputs.VSR_top(i,j)*cos(outputs.rollAngleTop(i,j));
%         outputs.reelOutF(i,j) = outputs.VRO_top(i,j)/outputs.Vw_top(i,j);


 %% Force balance, Only Aero, No gravity, No Centripetal
        
      
        % Bottom point
        
%         % Airspeed
%         outputs.Va_top(i,j) = outputs.Vc_top(i,j)/sqrt(1-(outputs.CD(i,j)/outputs.CL(i,j))^2);
%         
%          % Resultant Aero force
%         outputs.Fa_top(i,j) = outputs.halfRhoS(i,j)*outputs.CR(i,j)*outputs.Va_top(i,j)^2;
%         
%         % Tether force
%         outputs.T_top(i,j)   = min(outputs.Tmax_act, outputs.Fa_top(i,j));   
%           
%         % Sink rate in tether tension direction
%         outputs.VSR_top(i,j) = outputs.Va_top(i,j)*outputs.CD(i,j)/outputs.CL(i,j);
%        
%         % Reel-out speed
%         outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)-outputs.pattAngRadius(i))-outputs.VSR_top(i,j);
%         outputs.reelOutF(i,j) = outputs.VRO_top(i,j)/outputs.Vw_top(i,j);


%% Evaluating flight state equilibrium at the side point of the pattern
        
%         % Wind speed at pattern avg height
%         outputs.Vw_top(i,j) = inputs.vw_ref(i)*((outputs.h_inCycle(i,j)+outputs.pattRadius(i,j)*cos(outputs.pattAngRadius(i)))...
%                             /inputs.h_ref)^inputs.windShearExp;
%         
%         % Air density as a function of height   % Ref: https://en.wikipedia.org/wiki/Density_of_air
%         M = 0.0289644; % [kg/mol]
%         R = 8.3144598; % [N·m/(mol·K)]
%         T = 288.15;    % [Kelvin]
%         L = 0.0065;    % [Kelvin/m] 
%         outputs.rho_air(i,j) = inputs.airDensity*(1-L*(outputs.h_inCycle(i,j)+outputs.pattRadius(i,j)*cos(outputs.pattAngRadius(i)))/T)^(inputs.gravity*M/R/L-1); 
%         
%         % Intermediate calculation for brevity
%         outputs.lambda(i,j) = 0.5*outputs.rho_air(i,j)*inputs.WA*outputs.CL(i,j);
%         outputs.delta(i,j)  = 0.5*outputs.rho_air(i,j)*inputs.WA*outputs.CD(i,j);
%         
%         % Centripetal force
%          outputs.Fc_top(i,j) = outputs.m_eff(i)*outputs.Vc_top(i,j)^2/outputs.pattRadius(i,j);
%         
%         % Airspeed
%         outputs.Va_top(i,j) = sqrt((outputs.W(i)*cos(outputs.pattAngRadius(i))*cos(outputs.avgPattEle(i)))/(outputs.lambda(i,j)*...
%                                 cos(outputs.rollAngleTop(i,j))*sin(outputs.pitchAngle(i,j))));
%         
%          % Resultant Aero force
%         outputs.Fa_top(i,j) = outputs.Va_top(i,j)^2*sqrt(outputs.lambda(i,j)^2+outputs.delta(i,j)^2);
%         
%                               
%         % Tether force
%         outputs.T_top(i,j)   = min(outputs.Tmax_act, outputs.Fa_top(i,j)*cos(outputs.rollAngleTop(i,j))*cos(outputs.pitchAngle(i,j)) - ...
%                outputs.W(i)*cos(outputs.pattAngRadius(i)*sin(outputs.avgPattEle(i))-outputs.Fc_top(i,j)*sin(outputs.pattAngRadius(i))));
%                  
%         
%         % Sink rate
%         outputs.VSR_top(i,j) = outputs.Va_top(i,j)*outputs.CD(i,j)/outputs.CL(i,j)*cos(outputs.rollAngleTop(i,j));
% %         outputs.VSR_top2(i,j) = outputs.CD(i,j)/outputs.CL(i,j)^(3/2)*sqrt((outputs.T_top(i,j)+outputs.W(i)*sin(outputs.avgPattEle(i)+outputs.pattAngRadius(i))...
% %                 +outputs.Fc_top(i,j)*sin(outputs.avgPattEle(i)-outputs.pattAngRadius(i)))*cos(outputs.rollAngleTop(i,j))/(0.5*outputs.rho_air(i,j)*inputs.WA));
%            
%         % Reel-out speed
%         outputs.VRO_top(i,j) = outputs.Vw_top(i,j)*cos(outputs.avgPattEle(i)+outputs.pattAngRadius(i))-outputs.VSR_top(i,j);